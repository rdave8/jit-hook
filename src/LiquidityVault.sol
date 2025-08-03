// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

contract LiquidityVault is ERC20 {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using Math for uint256;
    using SafeERC20 for IERC20;

    IPoolManager immutable poolManager;
    PoolId poolId;
    
    IERC20 immutable token0;
    IERC20 immutable token1;

    uint160 immutable minSqrtPriceX96;
    uint160 immutable maxSqrtPriceX96;

    constructor(IPoolManager _poolManager, PoolKey memory _poolKey, address _hook, IERC20 _token0, IERC20 _token1, string memory vaultTokenName, string memory vaultTokenSymbol) ERC20(vaultTokenName, vaultTokenSymbol) {
        poolManager = _poolManager;
        poolId = _poolKey.toId();
        token0 = _token0;
        token1 = _token1;

        int24 tickSpacing = _poolKey.tickSpacing;
        minSqrtPriceX96 = TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing));
        maxSqrtPriceX96 = TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing));

        token0.approve(_hook, type(uint256).max);
        token1.approve(_hook, type(uint256).max);
    }

    function deposit(uint256 amount0, uint256 amount1) external returns (uint256 shares) {
        uint256 liquidity = amountsToLiquidity(amount0, amount1);
        uint256 totalSupply = totalSupply();

        if (totalSupply == 0) {
            shares = liquidity;
        } else {
            shares = liquidity.mulDiv(totalSupply, totalLiquidity());
        }

        _mint(msg.sender, shares);
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
    }

    function redeem(uint256 shares) external returns (uint256 amount0, uint256 amount1) {
        amount0 = token0.balanceOf(address(this)).mulDiv(shares, totalSupply());
        amount1 = token1.balanceOf(address(this)).mulDiv(shares, totalSupply());

        _burn(msg.sender, shares);
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);
    }

    function amountsToLiquidity(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        (,int24 tick,,) = poolManager.getSlot0(poolId);
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);

        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            amount0,
            amount1
        );
    }

    function totalLiquidity() internal view returns (uint256) {
        return amountsToLiquidity(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }
}