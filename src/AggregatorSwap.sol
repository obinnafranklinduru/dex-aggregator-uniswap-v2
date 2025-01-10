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
        address indexed sender, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    error SwapFailed();
    error InvalidPath();
    error DeadlinePassed();
    error TransferFailed();
    error InsufficientAmount();

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

    /**
     * @notice Swaps an exact amount of input tokens for output tokens
     * @param amountIn Amount of input tokens to send
     * @param amountOutMin Minimum amount of output tokens to receive
     * @param path Array of token addresses respresnting the swap path
     * @param recipient Address to recieve the output tokens
     * @param deadline deadline Unix timestamp after which the transaction will revert
     * @return amounts Array of amounts for each swap in the path
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external nonReentrant validPath(path) validDeadline(deadline) returns (uint256[] memory amounts) {
        if (amountIn == 0) revert InsufficientAmount();
        if (recipient == address(0)) revert("Invalid recipient");

        // Transfer tokens from sender to this contract
        bool success = IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        if (!success) revert TransferFailed();

        // Approve tokens from sender to this contract
        _approveRouter(path[0], amountIn);

        // Execute swap
        try uniswapRouterV2.swapExactTokensForTokens(amountIn, amountOutMin, path, recipient, deadline) returns (
            uint256[] memory _amounts
        ) {
            amounts = _amounts;
            emit SwapExecuted(msg.sender, path[0], path[path.length - 1], amountIn, amounts[amounts.length - 1]);
        } catch {
            revert SwapFailed();
        }
    }

    /**
     * @dev Approves the router to spend tokens
     * @param token The token to approve
     * @param amount The amount to approve
     */
    function _approveRouter(address _token, uint256 _amount) internal {
        IERC20(_token).approve(address(uniswapRouterV2), 0); // Reset inital approval
        IERC20(_token).approve(address(uniswapRouterV2), _amount);
    }
}
