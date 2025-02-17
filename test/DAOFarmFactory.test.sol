// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/DAOFarmFactory.sol";
import "../src/DAOFarm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./mocks/MockERC20.sol";

contract DAOFarmFactoryTest is Test {
    DAOFarmFactory public factory;
    address public owner;
    address public emergencyRecoveryAddress;
    address public feeAddress;
    address public user1;
    address public user2;
    
    MockERC20 public depositToken;
    MockERC20 public rewardsToken;
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant MAX_DEFAULT_FEE = 500; // 1%

    event CreateNitroPool(address nitroAddress);
    event SetDefaultFee(uint256 fee);
    event SetFeeAddress(address feeAddress);
    event SetEmergencyRecoveryAddress(address emergencyRecoveryAddress);
    event SetExemptedAddress(address exemptedAddress, bool isExempted);
    event SetNitroPoolOwner(address previousOwner, address newOwner);

    function setUp() public {
        owner = address(this);
        emergencyRecoveryAddress = address(0x1);
        feeAddress = address(0x2);
        user1 = address(0x3);
        user2 = address(0x4);

        // Deploy mock tokens
        depositToken = new MockERC20("Deposit Token", "DT", INITIAL_SUPPLY);
        rewardsToken = new MockERC20("Rewards Token", "RT", INITIAL_SUPPLY);

        // Deploy factory
        factory = new DAOFarmFactory(emergencyRecoveryAddress, feeAddress);
    }

    // Test constructor and initial state
    function testConstructor() public {
        assertEq(factory.emergencyRecoveryAddress(), emergencyRecoveryAddress, "Wrong emergency recovery address");
        assertEq(factory.feeAddress(), feeAddress, "Wrong fee address");
        assertEq(factory.defaultFee(), 0, "Default fee should be 0");
        assertEq(factory.owner(), owner, "Wrong owner");
    }

    function testConstructorZeroAddressReverts() public {
        vm.expectRevert("invalid");
        new DAOFarmFactory(address(0), feeAddress);

        vm.expectRevert("invalid");
        new DAOFarmFactory(emergencyRecoveryAddress, address(0));
    }

    // Test NitroPool creation
    function testCreateNitroPool() public {
        DAOFarm.Settings memory settings = DAOFarm.Settings({
            startTime: block.timestamp + 1 hours,
            endTime: block.timestamp + 1 days
        });

        vm.expectEmit(true, false, false, true);
        emit CreateNitroPool(address(0)); // We can't know the exact address, but we can check the event is emitted

        address nitroPool = factory.createNitroPool(IERC20(address(depositToken)), IERC20(address(rewardsToken)), settings);
        
        assertTrue(nitroPool != address(0), "NitroPool not created");
        assertEq(factory.nitroPoolsLength(), 1, "Wrong nitro pools count");
        assertEq(factory.getNitroPool(0), nitroPool, "Wrong nitro pool address");
        assertEq(factory.ownerNitroPoolsLength(owner), 1, "Wrong owner nitro pools count");
        assertEq(factory.getOwnerNitroPool(owner, 0), nitroPool, "Wrong owner nitro pool address");
    }

    // Test fee management
    function testSetDefaultFee() public {
        uint256 newFee = 300; // 0.6%
        
        vm.expectEmit(true, false, false, true);
        emit SetDefaultFee(newFee);
        
        factory.setDefaultFee(newFee);
        assertEq(factory.defaultFee(), newFee, "Wrong default fee");
    }

    function testSetDefaultFeeReverts() public {
        vm.expectRevert("invalid amount");
        factory.setDefaultFee(MAX_DEFAULT_FEE + 1);
    }

    function testSetDefaultFeeOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setDefaultFee(300);
    }

    // Test exempted addresses
    function testSetExemptedAddress() public {
        vm.expectEmit(true, false, false, true);
        emit SetExemptedAddress(user1, true);
        
        factory.setExemptedAddress(user1, true);
        assertTrue(factory.isExemptedAddress(user1), "Address should be exempted");
        assertEq(factory.exemptedAddressesLength(), 1, "Wrong exempted addresses count");
        assertEq(factory.getExemptedAddress(0), user1, "Wrong exempted address");

        // Test removing exempted address
        vm.expectEmit(true, false, false, true);
        emit SetExemptedAddress(user1, false);
        
        factory.setExemptedAddress(user1, false);
        assertFalse(factory.isExemptedAddress(user1), "Address should not be exempted");
        assertEq(factory.exemptedAddressesLength(), 0, "Wrong exempted addresses count after removal");
    }

    function testSetExemptedAddressZeroAddressReverts() public {
        vm.expectRevert("zero address");
        factory.setExemptedAddress(address(0), true);
    }

    function testSetExemptedAddressOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setExemptedAddress(user2, true);
    }

    // Test fee address management
    function testSetFeeAddress() public {
        address newFeeAddress = address(0x5);
        
        vm.expectEmit(true, false, false, true);
        emit SetFeeAddress(newFeeAddress);
        
        factory.setFeeAddress(newFeeAddress);
        assertEq(factory.feeAddress(), newFeeAddress, "Wrong fee address");
    }

    function testSetFeeAddressZeroAddressReverts() public {
        vm.expectRevert("zero address");
        factory.setFeeAddress(address(0));
    }

    function testSetFeeAddressOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setFeeAddress(user2);
    }

    // Test emergency recovery address management
    function testSetEmergencyRecoveryAddress() public {
        address newEmergencyAddress = address(0x6);
        
        vm.expectEmit(true, false, false, true);
        emit SetEmergencyRecoveryAddress(newEmergencyAddress);
        
        factory.setEmergencyRecoveryAddress(newEmergencyAddress);
        assertEq(factory.emergencyRecoveryAddress(), newEmergencyAddress, "Wrong emergency recovery address");
    }

    function testSetEmergencyRecoveryAddressZeroAddressReverts() public {
        vm.expectRevert("zero address");
        factory.setEmergencyRecoveryAddress(address(0));
    }

    function testSetEmergencyRecoveryAddressOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setEmergencyRecoveryAddress(user2);
    }

    // Test NitroPool fee calculation
    function testGetNitroPoolFee() public {
        // Set default fee
        uint256 defaultFee = 300;
        factory.setDefaultFee(defaultFee);

        // Create a nitro pool
        DAOFarm.Settings memory settings = DAOFarm.Settings({
            startTime: block.timestamp + 1 hours,
            endTime: block.timestamp + 1 days
        });
        address nitroPool = factory.createNitroPool(IERC20(address(depositToken)), IERC20(address(rewardsToken)), settings);

        // Test regular fee
        assertEq(factory.getNitroPoolFee(nitroPool, owner), defaultFee, "Wrong fee for non-exempted address");

        // Test exempted nitro pool
        factory.setExemptedAddress(nitroPool, true);
        assertEq(factory.getNitroPoolFee(nitroPool, owner), 0, "Fee should be 0 for exempted nitro pool");

        // Test exempted owner
        factory.setExemptedAddress(nitroPool, false);
        factory.setExemptedAddress(owner, true);
        assertEq(factory.getNitroPoolFee(nitroPool, owner), 0, "Fee should be 0 for exempted owner");
    }

    // Test NitroPool ownership transfer
    function testSetNitroPoolOwner() public {
        // Create a nitro pool
        DAOFarm.Settings memory settings = DAOFarm.Settings({
            startTime: block.timestamp + 1 hours,
            endTime: block.timestamp + 1 days
        });
        address nitroPool = factory.createNitroPool(IERC20(address(depositToken)), IERC20(address(rewardsToken)), settings);
        
        // Transfer ownership
        DAOFarm pool = DAOFarm(nitroPool);
        pool.transferOwnership(user1);
        
        // Verify ownership changes in factory
        assertEq(factory.ownerNitroPoolsLength(owner), 0, "Previous owner should have no pools");
        assertEq(factory.ownerNitroPoolsLength(user1), 1, "New owner should have one pool");
        assertEq(factory.getOwnerNitroPool(user1, 0), nitroPool, "Wrong pool address for new owner");
    }

    function testSetNitroPoolOwnerUnknownPoolReverts() public {
        vm.expectRevert("unknown nitroPool");
        factory.setNitroPoolOwner(owner, user1);
    }

    function testSetNitroPoolOwnerInvalidOwnerReverts() public {
        // Create a nitro pool
        DAOFarm.Settings memory settings = DAOFarm.Settings({
            startTime: block.timestamp + 1 hours,
            endTime: block.timestamp + 1 days
        });
        address nitroPool = factory.createNitroPool(IERC20(address(depositToken)), IERC20(address(rewardsToken)), settings);
        
        // Try to transfer ownership with wrong previous owner
        vm.prank(nitroPool);
        vm.expectRevert("invalid owner");
        factory.setNitroPoolOwner(user1, user2);
    }
}
