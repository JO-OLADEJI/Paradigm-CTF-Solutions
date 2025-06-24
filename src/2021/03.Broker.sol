// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface IUniswapV2Pair {
    // @audit-info: documented as a "low-level function" that should be called by the UniswapV2Router that performs "important safety checks"
    // basically a function that mints you LP tokens of a pair after adding liquidity (token transfers) to this pair. The tokens should be
    // equivalent in value based on the current price calculated by the pool, cause the LP tokens minted would be minimum of the tokens sent
    // proportional to that token reserve in the pool
    function mint(address to) external returns (uint liquidity);

    // @audit-info: internally tightly packs it's variables into one storage slot
    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );

    // @audit-info: documented as a "low-level function" that should be called by the UniswapV2Router that performs "important safety checks"
    // basically a function used for swapping 2 tokens or executing a flashswap when `data` argument is non-empty. This function is optimistic,
    // enforcing it's invariant (k) after initially transferring requested amount(s) out
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;

    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface ERC20Like {
    function transfer(address dst, uint qty) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint qty
    ) external returns (bool);

    function approve(address dst, uint qty) external returns (bool);

    function balanceOf(address who) external view returns (uint);
}

interface WETH9 is ERC20Like {
    function deposit() external payable;
}

// TODO: study other hacks caused my non-standard ERC20 tokens
// a simple overcollateralized loan bank which accepts WETH as collateral and a
// token for borrowing. 0% APRs
contract Broker {
    IUniswapV2Pair public pair;

    // @audit-notice: upon lookup of this address on mainnet, it has `18` decimals not the `9` that's supposedly posed by `WETH9`
    // it's also worth noting that the `fallback()` function on `WETH9` calls `deposit()` so it wouldn't revert when called with arbitrary calldata
    // For withdrawals, `target.transfer()` is used instead of the safer `target.call()`
    WETH9 public constant weth =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // @audit-info: has no conventional `decimals` variable but the total supply is denominated in `ether` so we can assume `18`
    ERC20Like public token;

    // @audit-info: stores the amount of `weth` an address has deposited into this contract
    mapping(address => uint256) public deposited;
    // @audit-info: stores the amount of `token` an address has borrowed from this contract
    mapping(address => uint256) public debt;

    // @audit-info: according to the `Setup`, the `_pair` is using `weth` and `_token` tokens
    constructor(IUniswapV2Pair _pair, ERC20Like _token) {
        pair = _pair;
        token = _token;
    }

    // @audit-info: gets the rate of `token0` to `token1` updated after calling `mint()`, `burn()`, `swap()` and `sync()` in the pair contract
    // @audit-notice: rate can be manipulated by depositing an unequally priced amount of `token0` and `token1` in pair contract and then calling `sync()`.
    function rate() public view returns (uint256) {
        (uint112 _reserve0, uint112 _reserve1, ) = pair.getReserves();

        // @audit-high: this division can run into cases that's not safe
        uint256 _rate = uint256(_reserve0 / _reserve1);
        return _rate;
    }

    // @audit-notice: I think things can go south here. `reserve0` and `reserve1` corresponds to `token0` and `token1` - order of which is determined by `token0` < `token1`
    // and the other `ERC20Like` token is deployed in the setup, which means it's also dependent on the `nonce` of the deployer.
    // In simple terms, the order of `token0` and `token1` is not guaranteed, therefore I think additional checks needs to be put in place to calculate an address' "safeDebt"
    //
    // The basic idea of this function is that a user can't borrow more than 2/3 the value of deposited collateral
    function safeDebt(address user) public view returns (uint256) {
        return (deposited[user] * rate() * 2) / 3;
    }

    // borrow some tokens
    function borrow(uint256 amount) public {
        debt[msg.sender] += amount;

        // @audit-notice: this function can suffer from the `safeDebt` vulnerability pointed out above
        require(
            safeDebt(msg.sender) >= debt[msg.sender],
            "err: undercollateralized"
        );

        // @audit-question: where does this contract get the tokens it lends out seeing that it only accepts deposits of `weth`?
        // @audit-answer: from the `Setup` the deployer sends `500_000` tokens to it.
        token.transfer(msg.sender, amount);
    }

    // repay your loan
    function repay(uint256 amount) public {
        // reduce user's debt
        debt[msg.sender] -= amount;

        // requires repayement to be approved with this contract as operator
        token.transferFrom(msg.sender, address(this), amount);
    }

    // repay a user's loan and get back their collateral. no discounts.
    function liquidate(address user, uint256 amount) public returns (uint256) {
        // requires loan to be undercollateralized before liquidation
        require(safeDebt(user) <= debt[user], "err: overcollateralized");

        // retrieve debt from liquidator
        debt[user] -= amount;
        token.transferFrom(msg.sender, address(this), amount);

        // calculate collateral and send to liquidator
        uint256 collateralValueRepaid = amount / rate();
        weth.transfer(msg.sender, collateralValueRepaid);

        return collateralValueRepaid;
    }

    // top up your collateral
    function deposit(uint256 amount) public {
        deposited[msg.sender] += amount;
        weth.transferFrom(msg.sender, address(this), amount);
    }

    // remove collateral
    function withdraw(uint256 amount) public {
        deposited[msg.sender] -= amount;
        require(
            safeDebt(msg.sender) >= debt[msg.sender],
            "err: undercollateralized"
        );

        weth.transfer(msg.sender, amount);
    }
}
