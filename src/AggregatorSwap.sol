// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title AggregatorSwap
 * @notice A contract for facilitating token swaps through Uniswap V2
 * @dev Implements various swap functions with safety checks and proper error handling
 */
contract AggregatorSwap is ReentrancyGuard, Ownable {
    UniswapV2Router02 public immutable uniswapRouterV2;
    address public immutable WETH;

    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    error InvalidPath();
    error DeadlinePassed();
    error InsufficientAmount();
    error TransferFailed();
    error SwapFailed();

    modifier validDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlinePassed();
        _;
    }

    modifier validPath(address[] calldata path) {
        if (path.length < 2) revert InvalidPath();
        _;
    }

    constructor(address _uniswapRouterV2) Ownable(msg.sender) {
        if (_uniswapRouterV2 == address(0)) revert("Zero address");
        uniswapRouterV2 = IUniswapV2Router02(_uniswapRouterV2);
        WETH = uniswapRouterV2.WETH();
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external NotShortPath(path) returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        IERC20(path[0]).approve(address(uniswapRouterV2), amountIn);

        uniswapRouterV2.swapExactTokensForTokens(amountIn, amountOutMin, path, recipient, deadline);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external NotShortPath(path) returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInMax);

        IERC20(path[0]).approve(address(uniswapRouterV2), amountInMax);

        uniswapRouterV2.swapTokensForExactTokens(amountOut, amountInMax, path, recipient, deadline);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address token, address recipient, uint256 deadline)
        external
        payable
        NotShortPath(path)
        returns (uint256[] memory amounts)
    {
        address;
        path[0] = WETH;
        path[1] = token;

        uniswapRouterV2.swapExactETHForTokens(amountOutMin, path, recipient, deadline);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        address token,
        uint256 amountInMax,
        address recipient,
        uint256 deadline
    ) external NotShortPath(path) returns (uint256[] memory amounts) {
        address;
        path[0] = token;
        path[1] = WETH;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInMax);

        IERC20(path[0]).approve(address(uniswapRouterV2), amountInMax);

        uniswapRouterV2.swapTokensForExactETH(amountOut, amountInMax, path, recipient, deadline);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address token,
        address recipient,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        address;
        path[0] = token;
        path[1] = WETH;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        IERC20(path[0]).approve(address(uniswapRouterV2), amountIn);

        uniswapRouterV2.swapExactTokensForETH(amountIn, amountOutMin, path, recipient, deadline);
    }

    function swapETHForExactTokens(uint256 amountOut, address token, address recipient, uint256 deadline)
        external
        payable
        NotShortPath(path)
        returns (uint256[] memory amounts)
    {
        address;
        path[0] = WETH;
        path[1] = token;

        uniswapRouterV2.swapETHForExactTokens(amountOut, path, recipient, deadline);
    }
}
