pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RiskManager} from "../RiskManager/RiskManager.sol";
import {MarginAccount} from "../MarginAccount/MarginAccount.sol";
import {Vault} from "../MarginPool/Vault.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {ITypes} from "../Interfaces/ITypes.sol";
import "hardhat/console.sol";

contract MarginManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    RiskManager public riskManager;
    IContractRegistry public contractRegistry;
    Vault public vault;
    // address public riskManager;
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
        riskManager = RiskManager(riskmgr);
    }

    function SetVault(address _vault) external {
        // onlyOwner
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        require(marginAccounts[msg.sender] == address(0x0));
        MarginAccount acc = new MarginAccount();
        marginAccounts[msg.sender] = address(acc);
        return address(acc);
        // acc.setparams
        // approve
    }

    // function openMarginAccount(address underlyingToken)
    //     external
    //     returns (address)
    // {
    //     require(
    //         marginAccounts[msg.sender] == address(0x0),
    //         "MM: Acc already exists"
    //     );
    //     require(
    //         allowedUnderlyingTokens[underlyingToken] == true,
    //         "MM: Underlying token invalid"
    //     );
    //     MarginAccount acc = new MarginAccount(underlyingToken);
    //     marginAccounts[msg.sender] = address(acc);
    //     return address(acc);
    //     // acc.setparams
    //     // approve
    // }
    //  function toggleAllowedUnderlyingToken(address token) external {
    //     require(token != address(0x0), "MM: Invalid token");
    //     allowedUnderlyingTokens[token] = !allowedUnderlyingTokens[token];
    // }
    function closeMarginAccount() external {
        /**
        close positions
        take interest
        return funds
        burn contract account and remove mappings
         */
    }

    function openPosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        require(
            !marginAcc.existingPosition(protocolAddress),
            "Existing position"
        );
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.verifyTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );
        marginAcc.updatePosition(
            protocolAddress,
            positionSize,
            uint256(absVal(tokensToTransfer)),
            true
        );
        if (tokensToTransfer > 0) {
            //vault.approve/transfer
        }

        // bytes memory returnData = marginAcc.execMultiTx(
        //     destinations,
        //     dataArray
        // );
        // do something with returnData or remove
        /**
        if RiskManager.AllowNewTrade
            open positions
         */
    }

    function updatePosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        require(
            marginAcc.existingPosition(protocolAddress),
            "Position doesn't exist"
        );
        int256 tokensToTransfer;
        int256 _currentPositionSize;
        int256 _oldPositionSize = marginAcc.getPositionValue(protocolAddress);
        (tokensToTransfer, _currentPositionSize) = riskManager.verifyTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );

        marginAcc.updatePosition(
            protocolAddress,
            _oldPositionSize + _currentPositionSize,
            uint256(absVal(tokensToTransfer)),
            true
        );
        if (tokensToTransfer > 0) {
            //vault.approve/transfer
        }
    }

    function closePosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        // address protocolAddress = marginAcc.positions(positionIndex);
        require(
            marginAcc.existingPosition(protocolAddress),
            "Position doesn't exist"
        );
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.closeTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );
        require(
            marginAcc.removePosition(protocolAddress),
            "Error in removing position"
        );
        /**
        if transfer margin back from protocol then reduce total debt and repay
        preview close on origin, if true close or revert
        take fees and interest
         */
    }

    function liquidatePosition(address protocolAddress) external {
        address marginAcc = marginAccounts[msg.sender];
        require(
            MarginAccount(marginAcc).existingPosition(protocolAddress),
            "Position doesn't exist"
        );
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

    function absVal(int256 val) public view returns (int256) {
        return val < 0 ? -val : val;
    }

    function _approveTokens() private {}
}
