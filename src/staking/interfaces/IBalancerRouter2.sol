// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

enum AddLiquidityKind {
    PROPORTIONAL,
    UNBALANCED,
    SINGLE_TOKEN_EXACT_OUT,
    DONATION,
    CUSTOM
}

enum RemoveLiquidityKind {
    PROPORTIONAL,
    SINGLE_TOKEN_EXACT_IN,
    SINGLE_TOKEN_EXACT_OUT,
    CUSTOM
}

library IAllowanceTransfer {
    struct PermitBatch {
        PermitDetails[] details;
        address spender;
        uint256 sigDeadline;
    }

    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }
}

library IRouter {
    struct InitializeHookParams {
        address sender;
        address pool;
        address[] tokens;
        uint256[] exactAmountsIn;
        uint256 minBptAmountOut;
        bool wethIsEth;
        bytes userData;
    }

}

library IRouterCommon {
    struct AddLiquidityHookParams {
        address sender;
        address pool;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }

    struct PermitApproval {
        address token;
        address owner;
        address spender;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    struct RemoveLiquidityHookParams {
        address sender;
        address pool;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        RemoveLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }
}

interface Router {
    type SwapKind is uint8;

    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error ErrorSelectorNotFound();
    error EthTransfer();
    error FailedInnerCall();
    error InputLengthMismatch();
    error InsufficientEth();
    error ReentrancyGuardReentrantCall();
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);
    error SafeERC20FailedOperation(address token);
    error SenderIsNotVault(address sender);
    error SwapDeadline();

    receive() external payable;

    function addLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);
    function addLiquidityHook(IRouterCommon.AddLiquidityHookParams memory params)
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn);
    function addLiquiditySingleTokenExactOut(
        address pool,
        address tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountIn);
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);
    function donate(address pool, uint256[] memory amountsIn, bool wethIsEth, bytes memory userData) external payable;
    function getSender() external view returns (address);
    function initialize(
        address pool,
        address[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);
    function initializeHook(IRouter.InitializeHookParams memory params) external returns (uint256 bptAmountOut);
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
    function permitBatchAndCall(
        IRouterCommon.PermitApproval[] memory permitBatch,
        bytes[] memory permitSignatures,
        IAllowanceTransfer.PermitBatch memory permit2Batch,
        bytes memory permit2Signature,
        bytes[] memory multicallData
    ) external payable returns (bytes[] memory results);
    function queryAddLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);
    function queryAddLiquidityHook(IRouterCommon.AddLiquidityHookParams memory params)
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);
    function queryAddLiquidityProportional(
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn);
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        address tokenIn,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountIn);
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);
    function queryRemoveLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);
    function queryRemoveLiquidityHook(IRouterCommon.RemoveLiquidityHookParams memory params)
        external
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);
    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
    function queryRemoveLiquidityRecovery(address pool, uint256 exactBptAmountIn)
        external
        returns (uint256[] memory amountsOut);
    function queryRemoveLiquidityRecoveryHook(address pool, address sender, uint256 exactBptAmountIn)
        external
        returns (uint256[] memory amountsOut);
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        address tokenOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountOut);
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        address tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountIn);
    function querySwapSingleTokenExactIn(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountCalculated);
    function querySwapSingleTokenExactOut(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountCalculated);
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);
    function removeLiquidityHook(IRouterCommon.RemoveLiquidityHookParams memory params)
        external
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);
    function removeLiquidityRecovery(address pool, uint256 exactBptAmountIn, uint256[] memory minAmountsOut)
        external
        payable
        returns (uint256[] memory amountsOut);
    function removeLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
    ) external returns (uint256[] memory amountsOut);
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountOut);
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        address tokenOut,
        uint256 exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn);
    function swapSingleTokenExactIn(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256);
    function swapSingleTokenExactOut(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256);
    function version() external view returns (string memory);
}
