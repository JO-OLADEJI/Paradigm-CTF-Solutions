pragma solidity 0.4.24;

import "../../src/2021/05.Swap.sol";

contract UniswapV2RouterLike {
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) public payable returns (uint[] memory amounts);
}

contract SetupSwap {
    StableSwap public swap;
    uint public value;

    constructor() public payable {
        swap = new StableSwap();

        UniswapV2RouterLike router = UniswapV2RouterLike(
            0xf164fC0Ec4E93095b804a4795bBe1e041497b92a // UniswapV2 router - mainnet
        );

        // @audit-notice: lookout for ERC20 tokens that don't revert on fail but return `false`
        // @audit-notice: lookout for rebase ERC20 tokens
        // @audit-notice: lookout for tokens that have multiple access points => TrueUSD
        ERC20Like[4] memory tokens = [
            ERC20Like(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI - mainnet | @audit-notice: flashloan mint on this token is possible
            ERC20Like(0x0000000000085d4780B73119b644AE5ecd22b376), // TrueUSD - mainnet | @audit-notice: I know this token is weird
            ERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // USDC - mainnet | @audit-notice: I know this token is a bit centralized
            ERC20Like(0xdAC17F958D2ee523a2206206994597C13D831ec7) // USDT - mainnet | @audit-notice: weird token e.g addresses can be blacklisted
        ];

        uint[] memory amounts = new uint[](4);

        for (uint i = 0; i < 4; i++) {
            swap.addCollateral(tokens[i]);

            address[] memory path = new address[](2);
            path[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH - mainnet
            path[1] = address(tokens[i]); // Each stablecoin in the `tokens` array

            router.swapExactETHForTokens.value(100 ether)(
                0,
                path,
                address(this),
                uint(-1)
            );

            tokens[i].approve(address(swap), uint(-1)); // @audit-info: approve `type(uint256).max` for `StableSwap` contract
            amounts[i] = tokens[i].balanceOf(address(this)); // @audit-info: store the received tokens amount in `amounts` array
        }

        swap.mint(amounts);

        value = swap.totalValue();
    }

    // @audit-info: criteria for passing this challenge is to reduce the `totalValue` of `StableSwap` contract to less than 1/100th it's original value
    function isSolved() public view returns (bool) {
        return swap.totalValue() < value / 100;
    }
}
