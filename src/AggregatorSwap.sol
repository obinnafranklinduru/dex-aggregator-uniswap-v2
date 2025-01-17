// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title AggregatorSwap
 * @notice A contract for facilitating token swaps and liquidity management through Uniswap V2
 * @dev Implements swap and liquidity functions with safety checks and proper error handling
 */
contract AggregatorSwap is ReentrancyGuard, Ownable {
    struct LiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address recipient;
        uint256 deadline;
    }

    struct RemoveLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
        address recipient;
        uint256 deadline;
    }

    IUniswapV2Router02 public immutable uniswapRouterV2;
    IUniswapV2Factory public immutable uniswapFactory;

    event SwapExecuted(
        address indexed sender, 
        address indexed tokenIn, 
        address indexed tokenOut, 
        uint256 amountIn, 
        uint256 amountOut
    );

    event LiquidityAdded(
        address indexed sender,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    event LiquidityRemoved(
        address indexed sender,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    error SwapFailed();
    error InvalidPath();
    error DeadlinePassed();
    error TransferFailed();
    error InsufficientAmount();
    error AddLiquidityFailed();
    error RemoveLiquidityFailed();
    error InsufficientLiquidity();
    error InvalidParams();

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
        uniswapFactory = IUniswapV2Factory(uniswapRouterV2.factory());
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external nonReentrant validPath(path) validDeadline(deadline) returns (uint256[] memory amounts) {
        if (amountIn == 0) revert InsufficientAmount();
        if (recipient == address(0)) revert("Invalid recipient");

        _handleTokenTransfers(path[0], amountIn);

        try uniswapRouterV2.swapExactTokensForTokens(amountIn, amountOutMin, path, recipient, deadline) returns (
            uint256[] memory _amounts
        ) {
            amounts = _amounts;
            emit SwapExecuted(msg.sender, path[0], path[path.length - 1], amountIn, amounts[amounts.length - 1]);
        } catch {
            revert SwapFailed();
        }
    }

    function swapETHForExactTokens(
        uint256 amountOut, 
        address token, 
        address recipient, 
        uint256 deadline
    )
        external
        payable
        nonReentrant
        validDeadline(deadline)
        returns (uint256[] memory amounts)
    {
        if (amountOut == 0) revert InsufficientAmount();
        if (token == address(0)) revert("Invalid token");
        if (recipient == address(0)) revert("Invalid recipient");

        address[] memory path = new address[](2);
        path[0] = address(uniswapRouterV2.WETH());
        path[1] = token;

        try uniswapRouterV2.swapETHForExactTokens{value: msg.value}(amountOut, path, recipient, deadline) returns (
            uint256[] memory _amounts
        ) {
            amounts = _amounts;
            emit SwapExecuted(msg.sender, address(uniswapRouterV2.WETH()), token, msg.value, amountOut);

            _refundExcessETH();
        } catch {
            revert SwapFailed();
        }
    }

    function addLiquidity(LiquidityParams calldata params)
        external
        nonReentrant
        validDeadline(params.deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        _validateLiquidityParams(params);

        _handleTokenTransfers(params.tokenA, params.amountADesired);
        _handleTokenTransfers(params.tokenB, params.amountBDesired);

        try uniswapRouterV2.addLiquidity(
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            params.amountAMin,
            params.amountBMin,
            params.recipient,
            params.deadline
        ) returns (uint256 _amountA, uint256 _amountB, uint256 _liquidity) {
            _handleRefunds(
                params.tokenA,
                params.tokenB,
                params.amountADesired,
                params.amountBDesired,
                _amountA,
                _amountB
            );

            emit LiquidityAdded(msg.sender, params.tokenA, params.tokenB, _amountA, _amountB, _liquidity);
            return (_amountA, _amountB, _liquidity);
        } catch {
            revert AddLiquidityFailed();
        }
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        nonReentrant
        validDeadline(params.deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        if (params.liquidity == 0) revert InsufficientLiquidity();

        address pair = uniswapFactory.getPair(params.tokenA, params.tokenB);
        if (pair == address(0)) revert("Pair does not exist");

        if (!IERC20(pair).transferFrom(msg.sender, address(this), params.liquidity)) revert TransferFailed();
        _approveRouter(pair, params.liquidity);

        try uniswapRouterV2.removeLiquidity(
            params.tokenA,
            params.tokenB,
            params.liquidity,
            params.amountAMin,
            params.amountBMin,
            params.recipient,
            params.deadline
        ) returns (uint256 _amountA, uint256 _amountB) {
            emit LiquidityRemoved(msg.sender, params.tokenA, params.tokenB, _amountA, _amountB, params.liquidity);
            return (_amountA, _amountB);
        } catch {
            revert RemoveLiquidityFailed();
        }
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address recipient,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        validDeadline(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        if (token == address(0)) revert("Invalid token");
        if (recipient == address(0)) revert("Invalid recipient");
        if (amountTokenDesired == 0 || msg.value == 0) revert InsufficientAmount();

        _handleTokenTransfers(token, amountTokenDesired);

        try uniswapRouterV2.addLiquidityETH{value: msg.value}(
            token,
            amountTokenDesired,
            amountTokenMin,
            amountETHMin,
            recipient,
            deadline
        ) returns (uint256 _amountToken, uint256 _amountETH, uint256 _liquidity) {
            if (amountTokenDesired > _amountToken) {
                IERC20(token).transfer(msg.sender, amountTokenDesired - _amountToken);
            }

            emit LiquidityAdded(
                msg.sender, 
                token, 
                address(uniswapRouterV2.WETH()), 
                _amountToken, 
                _amountETH, 
                _liquidity
            );
            return (_amountToken, _amountETH, _liquidity);
        } catch {
            revert AddLiquidityFailed();
        }
    }

    function _validateLiquidityParams(LiquidityParams memory params) internal pure {
        if (params.tokenA == address(0) || params.tokenB == address(0)) revert InvalidParams();
        if (params.recipient == address(0)) revert InvalidParams();
        if (params.amountADesired == 0 || params.amountBDesired == 0) revert InsufficientAmount();
    }

    function _handleTokenTransfers(address token, uint256 amount) internal {
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        _approveRouter(token, amount);
    }

    function _approveRouter(address token, uint256 amount) internal {
        IERC20(token).approve(address(uniswapRouterV2), 0);
        IERC20(token).approve(address(uniswapRouterV2), amount);
    }

    function _handleRefunds(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAUsed,
        uint256 amountBUsed
    ) internal {
        if (amountADesired > amountAUsed) {
            IERC20(tokenA).transfer(msg.sender, amountADesired - amountAUsed);
        }
        if (amountBDesired > amountBUsed) {
            IERC20(tokenB).transfer(msg.sender, amountBDesired - amountBUsed);
        }
    }

    function _refundExcessETH() internal {
        if (address(this).balance > 0) {
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert("ETH refund failed");
        }
    }

    function rescueTokens(address token, uint256 amount) external onlyOwner {
        bool success = IERC20(token).transfer(owner(), amount);
        if (!success) revert("Token rescue failed");
    }

    function rescueETH() external onlyOwner {
        (bool success,) = owner().call{value: address(this).balance}("");
        if (!success) revert("ETH rescue failed");
    }

    receive() external payable {}
    fallback() external payable {}
}