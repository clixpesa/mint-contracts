// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {AuthorityUtils} from "@openzeppelin/contracts/access/manager/AuthorityUtils.sol";
import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ShillingStable is ERC20, ERC20Burnable, ERC20Pausable, AccessManaged, ERC1363, ERC20Permit {
    using SafeERC20 for IERC20;

    // Chainlink price feeds
    AggregatorV3Interface public usdcUsdPriceFeed;
    AggregatorV3Interface public usdtUsdPriceFeed;
    AggregatorV3Interface public kesUsdPriceFeed;

    // Supported stablecoins for minting
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;

    // Chainlink CCIP Router
    IRouterClient public immutable ccipRouter;

    // Minting fee in basis points (0.3%)
    uint256 public constant MINT_FEE_BPS = 30;
    address public feeCollector;

    // Decimals for precision
    uint8 private constant PRICE_FEED_DECIMALS = 8;
    uint8 private constant STABLECOIN_DECIMALS = 6;
    uint8 private constant KES_DECIMALS = 18;

    // Cross-chain state
    mapping(uint64 => bool) public supportedChains;
    mapping(bytes32 => bool) public completedBridges;

    event MintedWithStablecoin(
        address indexed user,
        address indexed stablecoin,
        uint256 stablecoinAmount,
        uint256 kesAmount,
        uint256 fee
    );
    event RedeemedToStablecoin(
        address indexed user,
        address indexed stablecoin,
        uint256 kesAmount,
        uint256 stablecoinAmount,
        uint256 fee
    );
    event FeeCollectorUpdated(address newFeeCollector);
    event PriceFeedsUpdated(
        address usdcUsdPriceFeed,
        address usdtUsdPriceFeed,
        address kesUsdPriceFeed
    );
    event CrossChainTransferInitiated(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        uint256 amount
    );
    event CrossChainTransferCompleted(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed receiver,
        uint256 amount
    );
    event ChainSupportUpdated(uint64 chainSelector, bool supported);

    constructor(
        address initialAuthority,
        address _usdc,
        address _usdt,
        address _usdcUsdPriceFeed,
        address _usdtUsdPriceFeed,
        address _kesUsdPriceFeed,
        address _feeCollector,
        address _ccipRouter
    )
        ERC20("KES Shilling", "KxSH")
        AccessManaged(initialAuthority)
        ERC20Permit("KES Shilling")
    {
        require(_usdc != address(0), "Invalid USDC address");
        require(_usdt != address(0), "Invalid USDT address");
        require(_usdcUsdPriceFeed != address(0), "Invalid USDC price feed");
        require(_usdtUsdPriceFeed != address(0), "Invalid USDT price feed");
        require(_kesUsdPriceFeed != address(0), "Invalid KES price feed");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_ccipRouter != address(0), "Invalid CCIP router");

        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
        usdcUsdPriceFeed = AggregatorV3Interface(_usdcUsdPriceFeed);
        usdtUsdPriceFeed = AggregatorV3Interface(_usdtUsdPriceFeed);
        kesUsdPriceFeed = AggregatorV3Interface(_kesUsdPriceFeed);
        feeCollector = _feeCollector;
        ccipRouter = IRouterClient(_ccipRouter);
    }

    /**
     * @dev Mint KES tokens using USDC
     * @param usdcAmount Amount of USDC to deposit
     */
    function mintWithUSDC(uint256 usdcAmount) external whenNotPaused {
        _mintWithStablecoin(usdc, usdcAmount, usdcUsdPriceFeed);
    }

    /**
     * @dev Mint KES tokens using USDT
     * @param usdtAmount Amount of USDT to deposit
     */
    function mintWithUSDT(uint256 usdtAmount) external whenNotPaused {
        _mintWithStablecoin(usdt, usdtAmount, usdtUsdPriceFeed);
    }

    /**
     * @dev Redeem KES tokens for USDC
     * @param kesAmount Amount of KES to redeem
     */
    function redeemToUSDC(uint256 kesAmount) external whenNotPaused {
        _redeemToStablecoin(usdc, kesAmount, usdcUsdPriceFeed);
    }

    /**
     * @dev Redeem KES tokens for USDT
     * @param kesAmount Amount of KES to redeem
     */
    function redeemToUSDT(uint256 kesAmount) external whenNotPaused {
        _redeemToStablecoin(usdt, kesAmount, usdtUsdPriceFeed);
    }

    /**
     * @dev Initiate cross-chain transfer using Chainlink CCIP
     * @param destinationChainSelector The destination chain selector
     * @param receiver The receiver address on the destination chain
     * @param amount The amount of KES to transfer
     * @return messageId The CCIP message ID
     */
    function bridgeToChain(
        uint64 destinationChainSelector,
        address receiver,
        uint256 amount
    ) external whenNotPaused returns (bytes32 messageId) {
        require(supportedChains[destinationChainSelector], "Chain not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Burn tokens from sender
        _burn(msg.sender, amount);

        // Create CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(msg.sender, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        // Send CCIP message
        uint256 fee = ccipRouter.getFee(destinationChainSelector, message);
        messageId = ccipRouter.ccipSend{value: fee}(
            destinationChainSelector,
            message
        );

        emit CrossChainTransferInitiated(
            messageId,
            destinationChainSelector,
            receiver,
            amount
        );
    }

    /**
     * @dev Complete cross-chain transfer (called by CCIP receiver)
     * @param sourceChainSelector The source chain selector
     * @param receiver The receiver address on this chain
     * @param amount The amount of KES to mint
     * @param messageId The CCIP message ID
     */
    function completeBridge(
        uint64 sourceChainSelector,
        address receiver,
        uint256 amount,
        bytes32 messageId
    ) external restricted {
        require(!completedBridges[messageId], "Transfer already completed");
        require(supportedChains[sourceChainSelector], "Chain not supported");

        completedBridges[messageId] = true;
        _mint(receiver, amount);

        emit CrossChainTransferCompleted(
            messageId,
            sourceChainSelector,
            receiver,
            amount
        );
    }

    /**
     * @dev Internal function to handle minting with any supported stablecoin
     */
    function _mintWithStablecoin(
        IERC20 stablecoin,
        uint256 stablecoinAmount,
        AggregatorV3Interface priceFeed
    ) internal {
        require(stablecoinAmount > 0, "Amount must be greater than 0");

        // Get current prices
        (uint256 stablecoinPrice, uint256 kesPrice) = _getCurrentPrices(priceFeed);

        // Calculate KES amount to mint
        uint256 kesAmount = (stablecoinAmount * stablecoinPrice * (10 ** KES_DECIMALS)) / 
            (kesPrice * (10 ** STABLECOIN_DECIMALS));

        // Calculate and deduct fee
        uint256 fee = (kesAmount * MINT_FEE_BPS) / 10000;
        uint256 kesAmountAfterFee = kesAmount - fee;

        // Transfer stablecoin from user
        stablecoin.safeTransferFrom(msg.sender, address(this), stablecoinAmount);

        // Mint KES tokens to user
        _mint(msg.sender, kesAmountAfterFee);

        // Mint fee to fee collector
        if (fee > 0) {
            _mint(feeCollector, fee);
        }

        emit MintedWithStablecoin(
            msg.sender,
            address(stablecoin),
            stablecoinAmount,
            kesAmountAfterFee,
            fee
        );
    }

    /**
     * @dev Internal function to handle redeeming to any supported stablecoin
     */
    function _redeemToStablecoin(
        IERC20 stablecoin,
        uint256 kesAmount,
        AggregatorV3Interface priceFeed
    ) internal {
        require(kesAmount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= kesAmount, "Insufficient KES balance");

        // Get current prices
        (uint256 stablecoinPrice, uint256 kesPrice) = _getCurrentPrices(priceFeed);

        // Calculate stablecoin amount to send
        uint256 stablecoinAmount = (kesAmount * kesPrice * (10 ** STABLECOIN_DECIMALS)) / 
            (stablecoinPrice * (10 ** KES_DECIMALS));

        // Calculate and deduct fee
        uint256 fee = (stablecoinAmount * MINT_FEE_BPS) / 10000;
        uint256 stablecoinAmountAfterFee = stablecoinAmount - fee;

        // Check contract has enough stablecoin
        require(stablecoin.balanceOf(address(this)) >= stablecoinAmountAfterFee, 
            "Insufficient stablecoin reserves");

        // Burn user's KES tokens
        _burn(msg.sender, kesAmount);

        // Transfer stablecoin to user
        stablecoin.safeTransfer(msg.sender, stablecoinAmountAfterFee);

        // Transfer fee to fee collector
        if (fee > 0) {
            stablecoin.safeTransfer(feeCollector, fee);
        }

        emit RedeemedToStablecoin(
            msg.sender,
            address(stablecoin),
            kesAmount,
            stablecoinAmountAfterFee,
            fee
        );
    }

    /**
     * @dev Get current prices from Chainlink feeds
     */
    function _getCurrentPrices(AggregatorV3Interface stablecoinPriceFeed) 
        internal 
        view 
        returns (uint256 stablecoinPrice, uint256 kesPrice) 
    {
        (, int256 usdStablecoinPrice, , , ) = stablecoinPriceFeed.latestRoundData();
        (, int256 usdKesPrice, , , ) = kesUsdPriceFeed.latestRoundData();

        require(usdStablecoinPrice > 0, "Invalid stablecoin price");
        require(usdKesPrice > 0, "Invalid KES price");

        stablecoinPrice = uint256(usdStablecoinPrice);
        kesPrice = uint256(usdKesPrice);
    }

    /**
     * @dev Update price feed addresses
     */
    function updatePriceFeeds(
        address _usdcUsdPriceFeed,
        address _usdtUsdPriceFeed,
        address _kesUsdPriceFeed
    ) external restricted {
        require(_usdcUsdPriceFeed != address(0), "Invalid USDC price feed");
        require(_usdtUsdPriceFeed != address(0), "Invalid USDT price feed");
        require(_kesUsdPriceFeed != address(0), "Invalid KES price feed");

        usdcUsdPriceFeed = AggregatorV3Interface(_usdcUsdPriceFeed);
        usdtUsdPriceFeed = AggregatorV3Interface(_usdtUsdPriceFeed);
        kesUsdPriceFeed = AggregatorV3Interface(_kesUsdPriceFeed);

        emit PriceFeedsUpdated(_usdcUsdPriceFeed, _usdtUsdPriceFeed, _kesUsdPriceFeed);
    }

    /**
     * @dev Update fee collector address
     */
    function updateFeeCollector(address _feeCollector) external restricted {
        require(_feeCollector != address(0), "Invalid fee collector");
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }

    /**
     * @dev Update supported chains for cross-chain transfers
     */
    function updateChainSupport(uint64 chainSelector, bool supported) external restricted {
        supportedChains[chainSelector] = supported;
        emit ChainSupportUpdated(chainSelector, supported);
    }

    /**
     * @dev Withdraw any ERC20 token from contract (emergency use only)
     */
    function withdrawERC20(IERC20 token, uint256 amount) external restricted {
        token.safeTransfer(authority(), amount);
    }

    // The following functions are overrides required by Solidity.

    function pause() public restricted {
        _pause();
    }

    function unpause() public restricted {
        _unpause();
    }

    function mint(address to, uint256 amount) public restricted {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent)
        internal
        override(ERC20)
    {
        super._approve(owner, spender, value, emitEvent);
    }

    // Receive ETH for CCIP fees
    receive() external payable {}
}