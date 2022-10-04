pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {ITypes} from "../Interfaces/ITypes.sol";

import {MarginAccount} from "./MarginAccount.sol";
import "hardhat/console.sol";

contract MarginManager is ITypes, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    IRiskManager public riskManager;
    IContractRegistry public contractRegistry;
    address public vault;
    uint256 public liquidationPenaulty;
    mapping(address => address) public marginAccounts;
    mapping(address => bool) public allowedUnderlyingTokens;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed
    // allowed protocols set
    EnumerableSet.AddressSet private allowedProtocols;
    // function transferAccount(address from, address to) external {}

    modifier xyz() {
        _;
    }

    constructor(IContractRegistry _contractRegistry) {
        contractRegistry = _contractRegistry;
    }

    function SetCollatralRatio(address token, uint256 value)
        external
    //onlyOwner
    {
        collatralRatio[token] = value;
    }

    function SetPenaulty(uint256 value) external {
        // onlyOwner
        liquidationPenaulty = value;
    }

    function SetRiskManager(address riskmgr) external {
        // onlyOwner
        riskManager = IRiskManager(riskmgr);
    }

    // function set(address p){}
    function openMarginAccount(address underlyingToken)
        external
        returns (address)
    {
        require(
            marginAccounts[msg.sender] == address(0x0),
            "MM: Acc already exists"
        );
        require(
            allowedUnderlyingTokens[underlyingToken] == true,
            "MM: Underlying token invalid"
        );
        MarginAccount acc = new MarginAccount(underlyingToken);
        marginAccounts[msg.sender] = address(acc);
        return address(acc);
        // acc.setparams
        // approve
    }

    function toggleAllowedUnderlyingToken(address token) external {
        require(token != address(0x0), "MM: Invalid token");
        allowedUnderlyingTokens[token] = !allowedUnderlyingTokens[token];
    }

    function closeMarginAccount() external {
        /**
        close positions
        take interest
        return funds
        burn contract account and remove mappings
         */
    }

    // let's assume we allow only 5 tx at max
    function addPosition(
        bytes32[] memory contractName,
        txMetaType[] memory transactionMetadata,
        address[] memory contractAddress,
        bytes[] memory data
    ) external {
        console.log("Started tx");
        address[] memory destinations = new address[](5);
        bytes[] memory dataArray = new bytes[](5);
        uint256 tokensToTransfer; // transfer these many tokens from vault to credit account.
        address marginacc = marginAccounts[msg.sender];
        require(marginacc != address(0x0), "MM: No MarginAccount");
        require(
            transactionMetadata.length == contractName.length,
            "MM: No Array parity"
        );
        require(
            transactionMetadata.length == contractAddress.length,
            "MM: No Array parity"
        );
        require(
            transactionMetadata.length == data.length,
            "MM: No Array parity"
        );
        console.log("verifying trade now");
        (destinations, dataArray, tokensToTransfer) = riskManager.verifyTrade(
            marginacc,
            contractName,
            transactionMetadata,
            contractAddress,
            data
        );
        console.log("trade verified, executing next");

        //vault.approve/transfer
        bytes memory returnData = MarginAccount(marginacc).execMultiTx(
            destinations,
            dataArray
        );

        // do something with returnData or remove
        /**
        if RiskManager.AllowNewTrade
            open positions
         */
    }

    function updatePosition(address protocol, bytes calldata data) external {
        // if (riskManager.verifyTrade(data)) {
        //marginacc.execute
        // }
    }

    function closePosition() external {
        /**
        preview close on origin, if true close or revert
        take fees and interest
         */
    }

    function liquidatePosition() external {
        /**
        riskManager.isliquidatable()
        close on the venue
        take interest 
        add penaulty
         */
    }

    function RemoveCollateral() external {
        /**
        check margin, open positions
        withdraw
         */
    }

    function calcCreditAccountAccruedInterest(address marginacc)
        public
        view
        returns (uint256)
    {
        return 1;
    }

    function _approveTokens() private {}
}
