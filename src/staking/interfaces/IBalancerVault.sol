// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IBalancerVault {
    type AddLiquidityKind is uint8;
    type RemoveLiquidityKind is uint8;
    type SwapKind is uint8;
    type TokenType is uint8;
    type WrappingDirection is uint8;

    struct AddLiquidityParams {
        address pool;
        address to;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
        bytes userData;
    }

    struct BufferWrapOrUnwrapParams {
        SwapKind kind;
        WrappingDirection direction;
        address wrappedToken;
        uint256 amountGivenRaw;
        uint256 limitRaw;
    }

    struct HooksConfig {
        bool enableHookAdjustedAmounts;
        bool shouldCallBeforeInitialize;
        bool shouldCallAfterInitialize;
        bool shouldCallComputeDynamicSwapFee;
        bool shouldCallBeforeSwap;
        bool shouldCallAfterSwap;
        bool shouldCallBeforeAddLiquidity;
        bool shouldCallAfterAddLiquidity;
        bool shouldCallBeforeRemoveLiquidity;
        bool shouldCallAfterRemoveLiquidity;
        address hooksContract;
    }

    struct LiquidityManagement {
        bool disableUnbalancedLiquidity;
        bool enableAddLiquidityCustom;
        bool enableRemoveLiquidityCustom;
        bool enableDonation;
    }

    struct PoolRoleAccounts {
        address pauseManager;
        address swapFeeManager;
        address poolCreator;
    }

    struct RemoveLiquidityParams {
        address pool;
        address from;
        uint256 maxBptAmountIn;
        uint256[] minAmountsOut;
        RemoveLiquidityKind kind;
        bytes userData;
    }

    struct TokenConfig {
        address token;
        TokenType tokenType;
        address rateProvider;
        bool paysYieldFees;
    }

    struct VaultSwapParams {
        SwapKind kind;
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 amountGivenRaw;
        uint256 limitRaw;
        bytes userData;
    }

    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error AfterAddLiquidityHookFailed();
    error AfterInitializeHookFailed();
    error AfterRemoveLiquidityHookFailed();
    error AfterSwapHookFailed();
    error AllZeroInputs();
    error AmountGivenZero();
    error AmountInAboveMax(address tokenIn, uint256 amountIn, uint256 maxAmountIn);
    error AmountOutBelowMin(address tokenOut, uint256 amountOut, uint256 minAmountOut);
    error BalanceNotSettled();
    error BalanceOverflow();
    error BeforeAddLiquidityHookFailed();
    error BeforeInitializeHookFailed();
    error BeforeRemoveLiquidityHookFailed();
    error BeforeSwapHookFailed();
    error BptAmountInAboveMax(uint256 amountIn, uint256 maxAmountIn);
    error BptAmountOutBelowMin(uint256 amountOut, uint256 minAmountOut);
    error BufferAlreadyInitialized(address wrappedToken);
    error BufferNotInitialized(address wrappedToken);
    error BufferSharesInvalidOwner();
    error BufferSharesInvalidReceiver();
    error BufferTotalSupplyTooLow(uint256 totalSupply);
    error CannotReceiveEth();
    error CannotSwapSameToken();
    error DoesNotSupportAddLiquidityCustom();
    error DoesNotSupportDonation();
    error DoesNotSupportRemoveLiquidityCustom();
    error DoesNotSupportUnbalancedLiquidity();
    error DynamicSwapFeeHookFailed();
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidSpender(address spender);
    error FailedInnerCall();
    error FeePrecisionTooHigh();
    error HookAdjustedAmountInAboveMax(address tokenIn, uint256 amountIn, uint256 maxAmountIn);
    error HookAdjustedAmountOutBelowMin(address tokenOut, uint256 amountOut, uint256 minAmountOut);
    error HookAdjustedSwapLimit(uint256 amount, uint256 limit);
    error HookRegistrationFailed(address poolHooksContract, address pool, address poolFactory);
    error InputLengthMismatch();
    error InvalidAddLiquidityKind();
    error InvalidRemoveLiquidityKind();
    error InvalidToken();
    error InvalidTokenConfiguration();
    error InvalidTokenDecimals();
    error InvalidTokenType();
    error InvalidUnderlyingToken(address wrappedToken);
    error InvariantRatioAboveMax(uint256 invariantRatio, uint256 maxInvariantRatio);
    error InvariantRatioBelowMin(uint256 invariantRatio, uint256 minInvariantRatio);
    error IssuedSharesBelowMin(uint256 issuedShares, uint256 minIssuedShares);
    error MaxTokens();
    error MinTokens();
    error MultipleNonZeroInputs();
    error NotEnoughBufferShares();
    error NotEnoughUnderlying(address wrappedToken, uint256 expectedUnderlyingAmount, uint256 actualUnderlyingAmount);
    error NotEnoughWrapped(address wrappedToken, uint256 expectedWrappedAmount, uint256 actualWrappedAmount);
    error NotStaticCall();
    error NotVaultDelegateCall();
    error PauseBufferPeriodDurationTooLarge();
    error PercentageAboveMax();
    error PoolAlreadyInitialized(address pool);
    error PoolAlreadyRegistered(address pool);
    error PoolInRecoveryMode(address pool);
    error PoolNotInRecoveryMode(address pool);
    error PoolNotInitialized(address pool);
    error PoolNotPaused(address pool);
    error PoolNotRegistered(address pool);
    error PoolPauseWindowExpired(address pool);
    error PoolPaused(address pool);
    error PoolTotalSupplyTooLow(uint256 totalSupply);
    error ProtocolFeesExceedTotalCollected();
    error QueriesDisabled();
    error QueriesDisabledPermanently();
    error QuoteResultSpoofed();
    error ReentrancyGuardReentrantCall();
    error RouterNotTrusted();
    error SafeCastOverflowedIntToUint(int256 value);
    error SafeCastOverflowedUintToInt(uint256 value);
    error SafeERC20FailedOperation(address token);
    error SenderIsNotVault(address sender);
    error SwapFeePercentageTooHigh();
    error SwapFeePercentageTooLow();
    error SwapLimit(uint256 amount, uint256 limit);
    error TokenAlreadyRegistered(address token);
    error TokenNotRegistered(address token);
    error TokensMismatch(address pool, address expectedToken, address actualToken);
    error TradeAmountTooSmall();
    error VaultBuffersArePaused();
    error VaultIsNotUnlocked();
    error VaultNotPaused();
    error VaultPauseWindowDurationTooLarge();
    error VaultPauseWindowExpired();
    error VaultPaused();
    error WrapAmountTooSmall(address wrappedToken);
    error WrongProtocolFeeControllerDeployment();
    error WrongUnderlyingToken(address wrappedToken, address underlyingToken);
    error WrongVaultAdminDeployment();
    error WrongVaultExtensionDeployment();
    error ZeroDivision();

    event AggregateSwapFeePercentageChanged(address indexed pool, uint256 aggregateSwapFeePercentage);
    event AggregateYieldFeePercentageChanged(address indexed pool, uint256 aggregateYieldFeePercentage);
    event Approval(address indexed pool, address indexed owner, address indexed spender, uint256 value);
    event AuthorizerChanged(address indexed newAuthorizer);
    event BufferSharesBurned(address indexed wrappedToken, address indexed from, uint256 burnedShares);
    event BufferSharesMinted(address indexed wrappedToken, address indexed to, uint256 issuedShares);
    event LiquidityAdded(
        address indexed pool,
        address indexed liquidityProvider,
        AddLiquidityKind indexed kind,
        uint256 totalSupply,
        uint256[] amountsAddedRaw,
        uint256[] swapFeeAmountsRaw
    );
    event LiquidityAddedToBuffer(
        address indexed wrappedToken, uint256 amountUnderlying, uint256 amountWrapped, bytes32 bufferBalances
    );
    event LiquidityRemoved(
        address indexed pool,
        address indexed liquidityProvider,
        RemoveLiquidityKind indexed kind,
        uint256 totalSupply,
        uint256[] amountsRemovedRaw,
        uint256[] swapFeeAmountsRaw
    );
    event LiquidityRemovedFromBuffer(
        address indexed wrappedToken, uint256 amountUnderlying, uint256 amountWrapped, bytes32 bufferBalances
    );
    event PoolInitialized(address indexed pool);
    event PoolPausedStateChanged(address indexed pool, bool paused);
    event PoolRecoveryModeStateChanged(address indexed pool, bool recoveryMode);
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        TokenConfig[] tokenConfig,
        uint256 swapFeePercentage,
        uint32 pauseWindowEndTime,
        PoolRoleAccounts roleAccounts,
        HooksConfig hooksConfig,
        LiquidityManagement liquidityManagement
    );
    event ProtocolFeeControllerChanged(address indexed newProtocolFeeController);
    event Swap(
        address indexed pool,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFeePercentage,
        uint256 swapFeeAmount
    );
    event SwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);
    event Transfer(address indexed pool, address indexed from, address indexed to, uint256 value);
    event Unwrap(
        address indexed wrappedToken, uint256 burnedShares, uint256 withdrawnUnderlying, bytes32 bufferBalances
    );
    event VaultAuxiliary(address indexed pool, bytes32 indexed eventKey, bytes eventData);
    event VaultBuffersPausedStateChanged(bool paused);
    event VaultPausedStateChanged(bool paused);
    event VaultQueriesDisabled();
    event VaultQueriesEnabled();
    event Wrap(address indexed wrappedToken, uint256 depositedUnderlying, uint256 mintedShares, bytes32 bufferBalances);

    fallback() external payable;

    receive() external payable;

    function addLiquidity(AddLiquidityParams memory params)
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);
    function erc4626BufferWrapOrUnwrap(BufferWrapOrUnwrapParams memory params)
        external
        returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw);
    function getPoolTokenCountAndIndexOfToken(address pool, address token) external view returns (uint256, uint256);
    function getVaultExtension() external view returns (address);
    function reentrancyGuardEntered() external view returns (bool);
    function removeLiquidity(RemoveLiquidityParams memory params)
        external
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);
    function sendTo(address token, address to, uint256 amount) external;
    function settle(address token, uint256 amountHint) external returns (uint256 credit);
    function swap(VaultSwapParams memory vaultSwapParams)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);
    function transfer(address owner, address to, uint256 amount) external returns (bool);
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);
    function unlock(bytes memory data) external returns (bytes memory result);
    function pausePool(address pool) external;
    function unpausePool(address pool) external;
    function getPoolPausedState(address pool) external view returns (bool,uint32,uint32,address);
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory);
}
