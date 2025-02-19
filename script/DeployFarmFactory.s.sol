// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {Script, console} from "forge-std/Script.sol";
import {DAOFarmFactory} from "../src/DAOFarmFactory.sol";

contract DeployFarmFactoryScript is Script {
    // Configuration
    address public CARTEL_TOKEN_ADDRESS = 0x98E0AD23382184338dDcEC0E13685358EF845f30;

    address public FEE_ADDRESS = 0x6F1313f206dB52139EB6892Bfd88aC9Ae36Dc54E;

    function run() public {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy WhitelistNFTLottery
        DAOFarmFactory farmFactory = new DAOFarmFactory(FEE_ADDRESS, FEE_ADDRESS);
        console.log("Deployed DAOFarmFactory at:", address(farmFactory));

        vm.stopBroadcast();
    }
}

// forge script script/DeployFarmFactory.s.sol:DeployFarmFactoryScript \
//   --rpc-url $RPC_URL \
//   --private-key $PRIVATE_KEY \
//   --broadcast \
//   --verify \
//   --verifier blockscout \
//   --verifier-url https://explorer.mode.network/api/

// forge verify-contract --rpc-url https://mainnet.mode.network/ 0x1a66EDB7058134798CBA6dbA91EFf98A84A7c6a8 ./src/DAOFarm.sol:DAOFarm --verifier blockscout --verifier-url https://explorer.mode.network/api
