// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AggregatorSwap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract AggregatorSwapTest is Test {
    AggregatorSwap public aggregator;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    address public owner;
    address public user;
    uint256 public constant DEADLINE = block.timestamp + 1 days;

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

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        
        // Deploy AggregatorSwap
        aggregator = new AggregatorSwap(UNISWAP_ROUTER);
        
        // Fund test addresses
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        
        // Impersonate and fund with tokens
        deal(DAI, user, 1000000 * 1e18);
        deal(USDC, user, 1000000 * 1e6);
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(user);
        
        uint256 amountIn = 1000 * 1e18; // 1000 DAI
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = USDC;
        
        // Approve DAI
        IERC20(DAI).approve(address(aggregator), amountIn);
        
        // Get initial balances
        uint256 initialDAIBalance = IERC20(DAI).balanceOf(user);
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(user);
        
        // Expect SwapExecuted event
        vm.expectEmit(true, true, true, false);
        emit SwapExecuted(user, DAI, USDC, amountIn, 0);
        
        // Execute swap
        uint256[] memory amounts = aggregator.swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount of USDC
            path,
            user,
            DEADLINE
        );
        
        // Verify balances changed
        assertEq(IERC20(DAI).balanceOf(user), initialDAIBalance - amountIn);
        assertGt(IERC20(USDC).balanceOf(user), initialUSDCBalance);
        
        vm.stopPrank();
    }

    function testSwapETHForExactTokens() public {
        vm.startPrank(user);
        
        uint256 amountOut = 1000 * 1e6; // 1000 USDC
        uint256 maxETH = 1 ether;
        
        // Get initial balances
        uint256 initialETHBalance = user.balance;
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(user);
        
        // Expect SwapExecuted event
        vm.expectEmit(true, true, true, false);
        emit SwapExecuted(user, WETH, USDC, maxETH, amountOut);
        
        // Execute swap
        uint256[] memory amounts = aggregator.swapETHForExactTokens{value: maxETH}(
            amountOut,
            USDC,
            user,
            DEADLINE
        );
        
        // Verify balances changed
        assertLt(user.balance, initialETHBalance);
        assertEq(IERC20(USDC).balanceOf(user), initialUSDCBalance + amountOut);
        
        vm.stopPrank();
    }

    function testAddLiquidity() public {
        vm.startPrank(user);
        
        uint256 amountDAI = 1000 * 1e18;
        uint256 amountUSDC = 1000 * 1e6;
        
        // Approve tokens
        IERC20(DAI).approve(address(aggregator), amountDAI);
        IERC20(USDC).approve(address(aggregator), amountUSDC);
        
        // Create liquidity params
        AggregatorSwap.LiquidityParams memory params = AggregatorSwap.LiquidityParams({
            tokenA: DAI,
            tokenB: USDC,
            amountADesired: amountDAI,
            amountBDesired: amountUSDC,
            amountAMin: 0,
            amountBMin: 0,
            recipient: user,
            deadline: DEADLINE
        });
        
        // Expect LiquidityAdded event
        vm.expectEmit(true, true, true, false);
        emit LiquidityAdded(user, DAI, USDC, 0, 0, 0);
        
        // Add liquidity
        (uint256 amountA, uint256 amountB, uint256 liquidity) = aggregator.addLiquidity(params);
        
        // Verify liquidity minted
        assertGt(liquidity, 0);
        assertGt(amountA, 0);
        assertGt(amountB, 0);
        
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        // First add liquidity
        testAddLiquidity();
        
        vm.startPrank(user);
        
        // Get pair address
        address pair = IUniswapV2Factory(aggregator.uniswapFactory()).getPair(DAI, USDC);
        uint256 liquidityBalance = IERC20(pair).balanceOf(user);
        
        // Approve LP tokens
        IERC20(pair).approve(address(aggregator), liquidityBalance);
        
        // Create remove liquidity params
        AggregatorSwap.RemoveLiquidityParams memory params = AggregatorSwap.RemoveLiquidityParams({
            tokenA: DAI,
            tokenB: USDC,
            liquidity: liquidityBalance,
            amountAMin: 0,
            amountBMin: 0,
            recipient: user,
            deadline: DEADLINE
        });
        
        // Expect LiquidityRemoved event
        vm.expectEmit(true, true, true, false);
        emit LiquidityRemoved(user, DAI, USDC, 0, 0, liquidityBalance);
        
        // Remove liquidity
        (uint256 amountA, uint256 amountB) = aggregator.removeLiquidity(params);
        
        // Verify tokens received
        assertGt(amountA, 0);
        assertGt(amountB, 0);
        
        vm.stopPrank();
    }

    function testAddLiquidityETH() public {
        vm.startPrank(user);
        
        uint256 amountToken = 1000 * 1e18; // 1000 DAI
        uint256 amountETH = 1 ether;
        
        // Approve DAI
        IERC20(DAI).approve(address(aggregator), amountToken);
        
        // Get initial balances
        uint256 initialETHBalance = user.balance;
        uint256 initialDAIBalance = IERC20(DAI).balanceOf(user);
        
        // Expect LiquidityAdded event
        vm.expectEmit(true, true, true, false);
        emit LiquidityAdded(user, DAI, WETH, 0, 0, 0);
        
        // Add liquidity
        (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) = aggregator.addLiquidityETH{value: amountETH}(
            DAI,
            amountToken,
            0, // amountTokenMin
            0, // amountETHMin
            user,
            DEADLINE
        );
        
        // Verify liquidity minted
        assertGt(liquidity, 0);
        assertGt(tokenAmount, 0);
        assertGt(ethAmount, 0);
        assertLt(user.balance, initialETHBalance);
        assertLt(IERC20(DAI).balanceOf(user), initialDAIBalance);
        
        vm.stopPrank();
    }

    function testRescueTokens() public {
        // Send some tokens to contract
        deal(DAI, address(aggregator), 1000 * 1e18);
        uint256 amount = IERC20(DAI).balanceOf(address(aggregator));
        
        // Only owner can rescue
        vm.prank(user);
        vm.expectRevert();
        aggregator.rescueTokens(DAI, amount);
        
        // Owner can rescue
        uint256 initialBalance = IERC20(DAI).balanceOf(owner);
        aggregator.rescueTokens(DAI, amount);
        assertEq(IERC20(DAI).balanceOf(owner), initialBalance + amount);
    }

    function testRescueETH() public {
        // Send some ETH to contract
        vm.deal(address(aggregator), 1 ether);
        
        // Only owner can rescue
        vm.prank(user);
        vm.expectRevert();
        aggregator.rescueETH();
        
        // Owner can rescue
        uint256 initialBalance = owner.balance;
        aggregator.rescueETH();
        assertEq(owner.balance, initialBalance + 1 ether);
    }

    function testInvalidDeadline() public {
        vm.warp(DEADLINE + 1);
        
        vm.startPrank(user);
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = USDC;
        
        vm.expectRevert(AggregatorSwap.DeadlinePassed.selector);
        aggregator.swapExactTokensForTokens(1000 * 1e18, 0, path, user, DEADLINE);
        
        vm.stopPrank();
    }

    receive() external payable {}
}