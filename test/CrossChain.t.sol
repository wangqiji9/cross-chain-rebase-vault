
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {CCIPLocalSimulatorFork, Register} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "../lib/chainlink-local/lib/chainlink-evm/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "../lib/chainlink-ccip/chains/evm/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "../lib/chainlink-ccip/chains/evm/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "../lib/chainlink-ccip/chains/evm/contracts/pools/TokenPool.sol";
import {RateLimiter} from "../lib/chainlink-ccip/chains/evm/contracts/libraries/RateLimiter.sol";
import {Client} from "../lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";
import {IRouterClient} from "../lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouterClient.sol";
import {Register} from "../lib/chainlink-local/src/ccip/Register.sol";

contract CrossChainTest is Test {
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 SEND_VALUE = 1e5;
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Vault vault;    

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbsepoliaNetworkDetails;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;


    function setUp() public {

        string memory SOURCE_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory DESTINATION_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        
        sepoliaFork = vm.createSelectFork(SOURCE_RPC_URL);
        arbSepoliaFork = vm.createFork(DESTINATION_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        //1.deploy and config on sepolia
        vm.startPrank(owner);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sepoliaToken = new RebaseToken();
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)), 
            new address[](0), 
            sepoliaNetworkDetails.rmnProxyAddress, 
            sepoliaNetworkDetails.routerAddress);
        
        vault = new Vault(IRebaseToken(address(sepoliaToken)));    
        vm.deal(address(vault), 1e18);
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));

        registryModuleOwnerCustomSepolia = 
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sepoliaToken));

        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistrySepolia.acceptAdminRole(address(sepoliaToken));
        tokenAdminRegistrySepolia.setPool(address(sepoliaToken), address(sepoliaTokenPool));
        vm.stopPrank();

        //2.deploy and configure on arbitrum sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbsepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)), 
            new address[](0), 
            arbsepoliaNetworkDetails.rmnProxyAddress, 
            arbsepoliaNetworkDetails.routerAddress);
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));  

        registryModuleOwnerCustomarbSepolia = RegistryModuleOwnerCustom(arbsepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(address(arbSepoliaToken));
        tokenAdminRegistryarbSepolia = TokenAdminRegistry(arbsepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryarbSepolia.acceptAdminRole(address(arbSepoliaToken));
        tokenAdminRegistryarbSepolia.setPool(address(arbSepoliaToken), address(arbSepoliaTokenPool));
        vm.stopPrank();  
    }

    function configureTokenPool(
        uint256 fork, 
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
        ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePooladdressesBytesArray = new bytes[](1);
        remotePooladdressesBytesArray[0] = abi.encode(address(remotePool));
        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePooladdressesBytesArray,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        localPool.applyChainUpdates(remoteChainSelectorsToRemove, chainToAdd);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    )public {
        vm.selectFork(localFork);
        vm.startPrank(user);
        Client.EVMTokenAmount[] memory tokenToSendDetails  = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = 
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenToSendDetails,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: ""
        });
        vm.stopPrank();

        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message));
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress, 
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message));
        
        //IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        
        uint256 localBalanceBefore = localToken.balanceOf(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
    }

    function testBridgeAllTokens() public{
        configureTokenPool(
            sepoliaFork, sepoliaTokenPool, arbSepoliaTokenPool, IRebaseToken(address(arbSepoliaToken)), arbsepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, arbSepoliaTokenPool, sepoliaTokenPool, IRebaseToken(address(sepoliaToken)), sepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        console.log("Bridging %d tokens", SEND_VALUE);
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        vm.stopPrank();
        bridgeTokens(SEND_VALUE, sepoliaFork,arbSepoliaFork,sepoliaNetworkDetails
        ,arbsepoliaNetworkDetails,sepoliaToken,arbSepoliaToken);
    }

    function testBridgeAllTokensBack() public {
        configureTokenPool(
            sepoliaFork, sepoliaTokenPool, arbSepoliaTokenPool, IRebaseToken(address(arbSepoliaToken)), arbsepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, arbSepoliaTokenPool, sepoliaTokenPool, IRebaseToken(address(sepoliaToken)), sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sepoliaToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge ALL TOKENS to the destination chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbsepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        console.log("User Balance Before Warp: %d", arbSepoliaToken.balanceOf(user));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", arbSepoliaToken.balanceOf(user));
        uint256 destBalance = IERC20(address(arbSepoliaToken)).balanceOf(user);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbsepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }

}