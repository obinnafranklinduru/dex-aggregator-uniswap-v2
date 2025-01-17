// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {AggregatorSwap} from "../src/AggregatorSwap.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract AggregatorSwapTest is Test {
    AggregatorSwap public aggregatorSwap;
    IUniswapV2Router02 public uniswapRouter;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public owner = address(0x123);
    address public user = address(0x456);

    function setUp() public {
        uniswapRouter = IUniswapV2Router02(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
        tokenA = MockERC20(address(new MockERC20("TokenA", "TKA")));
        tokenB = MockERC20(address(new MockERC20("TokenB", "TKB")));

        aggregatorSwap = new AggregatorSwap(address(uniswapRouter));
        aggregatorSwap.transferOwnership(owner);

        tokenA.mint(user, 1000 ether);
        tokenB.mint(user, 1000 ether);
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(user);
        tokenA.transfer(address(aggregatorSwap), 100 ether);
        tokenA.approve(address(aggregatorSwap), 100 ether);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = aggregatorSwap.swapExactTokensForTokens(
            100 ether, 1 ether, path, user, block.timestamp + 1 hours
        );

        assertEq(amounts[0], 100 ether);
        assertEq(tokenB.balanceOf(user), amounts[amounts.length - 1]);
        vm.stopPrank();
    }

    function testSwapETHForExactTokens() public {
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256[] memory amounts = aggregatorSwap.swapETHForExactTokens{value: 1 ether}(
            10 ether, address(tokenB), user, block.timestamp + 1 hours
        );

        // assertEq(amounts[amounts.length - 1], 10 ether);
        // assertEq(tokenB.balanceOf(user), 10 ether);
        vm.stopPrank();
    }

    function testRescueTokens() public {
        vm.prank(user);
        tokenA.transfer(address(aggregatorSwap), 100 ether);
        
        vm.startPrank(owner);
        aggregatorSwap.rescueTokens(address(tokenA), 100 ether);
        assertEq(tokenA.balanceOf(owner), 100 ether);
        vm.stopPrank();
    }

    function testRescueETH() public {
        vm.deal(address(aggregatorSwap), 1 ether);
        vm.startPrank(owner);
        aggregatorSwap.rescueETH();
        assertEq(owner.balance, 1 ether);
        vm.stopPrank();
    }
}