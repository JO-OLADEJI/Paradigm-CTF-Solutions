pragma solidity 0.4.24;

import "./05.ERC20.sol";
import "./05.ReentrancyGuard.sol";

contract StableSwap is ReentrancyGuard {
    // @audit-info                                                          STORAGE LAYOUT
    // ReentrancyGuard._status (_NOT_ENTERED = 1, _ENTERED = 2)                       0x00
    address private owner; //                                                         0x01
    ERC20Like[] public underlying; //                                                 0x02
    mapping(address => bool) public hasUnderlying; //                                 0x03
    uint private supply; //                                                           0x04
    mapping(address => uint) private balances; //                                     0x05
    mapping(address => mapping(address => uint)) private approvals; //                0x06

    constructor() public {
        owner = msg.sender;
    }

    struct MintVars {
        // amount of LP tokens in circulation
        uint totalSupply;
        // ---
        // normalized (to `18` decimals) this contract's balance of underlying tokens before receiving liquidity
        uint totalBalanceNorm;
        // ---
        // normalized (to `18` decimals) the total underlying tokens received by this contract
        uint totalInNorm;
        uint amountToMint;
        // ---
        // address of ERC20 (stablecoin) currently being used to provide liquidity
        ERC20Like token;
        // ---
        // `token` balance of `msg.sender`
        uint has;
        // ---
        // `token` balance of this contract before receiving liquidty
        uint preBalance;
        // ---
        // `token` balance of this contract after receiving liquidty
        uint postBalance;
        // ---
        // net difference between `postBalance` and `preBalance`, reflecting the exact amount this contract received
        uint deposited;
    }

    // @audit-info: send fresh LP tokens to an address in proportion to the liquidity specified in `amounts`
    function mint(uint[] memory amounts) public nonReentrant returns (uint) {
        MintVars memory v;
        v.totalSupply = supply;

        for (uint i = 0; i < underlying.length; i++) {
            v.token = underlying[i];

            v.preBalance = v.token.balanceOf(address(this));

            v.has = v.token.balanceOf(msg.sender);

            // @audit-info: if `amount` of underlying token is more than the `msg.sender` balance of that token,
            // then replace the `amount` with the sender's balance.
            // basically `amounts[i]` <= token.balanceOf(msg.sender)
            if (amounts[i] > v.has) amounts[i] = v.has;

            // @audit-info: transfer the `amount` from the sender to this contract
            v.token.transferFrom(msg.sender, address(this), amounts[i]);

            v.postBalance = v.token.balanceOf(address(this));

            v.deposited = v.postBalance - v.preBalance;

            v.totalBalanceNorm += scaleFrom(v.token, v.preBalance);

            v.totalInNorm += scaleFrom(v.token, v.deposited);
        }

        // first liquidity provider gets LP tokens equal to net liquidity received by this contract
        if (v.totalSupply == 0) {
            v.amountToMint = v.totalInNorm;
        }
        // other liquidity providers get LP tokens proportional to the balance of liquidity already held by this contract
        else {
            v.amountToMint =
                (v.totalInNorm * v.totalSupply) /
                v.totalBalanceNorm;
        }

        supply += v.amountToMint;
        balances[msg.sender] += v.amountToMint;

        return v.amountToMint;
    }

    struct BurnVars {
        // amount of LP tokens in circulation
        uint supply;
        // ---
        // a single underlying `token` balance of this contract before sending liquidty
        uint haveBalance;
        // ---
        // single underlying `token` amount to send to a liquidity provider
        uint sendBalance;
    }

    // @audit-info: converts LP tokens to underlying tokens, proportional to their balances held in this contract
    function burn(uint amount) public nonReentrant {
        require(balances[msg.sender] >= amount, "burn/low-balance");

        BurnVars memory v;
        v.supply = supply;

        for (uint i = 0; i < underlying.length; i++) {
            v.haveBalance = underlying[i].balanceOf(address(this));

            // @audit-notiice: proportional withdrawal of liquidity from `underlying` tokens
            v.sendBalance = (v.haveBalance * amount) / v.supply;

            underlying[i].transfer(msg.sender, v.sendBalance);
        }

        supply -= amount;
        balances[msg.sender] -= amount;
    }

    struct SwapVars {
        // this contract's balance of `src` ERC20 token before pulling funds from sender
        // also this contract's balance of `dst` ERC20 token before sending funds to user
        uint preBalance;
        // ---
        // this contract's balance of `src` ERC20 token after pulling funds from sender
        // also this contract's balance of `dst` ERC20 token after sending funds to user
        uint postBalance;
        // ---
        // net-inflow of `src` token - after misc fees (with 0.3% fee applied)
        uint input;
        // ---
        // calculated amount of `dst` tokens to be sent to caller based on `input`
        uint output;
        // ---
        // net-outflow of `dst` token - after misc fees
        uint sent;
    }

    function swap(
        ERC20Like src,
        uint srcAmt,
        ERC20Like dst
    ) public nonReentrant {
        require(hasUnderlying[address(src)], "swap/invalid-src");
        require(hasUnderlying[address(dst)], "swap/invalid-dst");

        SwapVars memory v;

        v.preBalance = src.balanceOf(address(this));
        src.transferFrom(msg.sender, address(this), srcAmt);
        v.postBalance = src.balanceOf(address(this));

        // @audit-info: net-inflow (minus 0.3% fee)
        v.input = ((v.postBalance - v.preBalance) * 997) / 1000;

        // @audit-info: converts normalized amountIn to native decimals of `dst` ERC20 token
        v.output = scaleTo(dst, scaleFrom(src, v.input));

        v.preBalance = dst.balanceOf(address(this));
        dst.transfer(msg.sender, v.output);
        v.postBalance = dst.balanceOf(address(this));

        v.sent = (v.preBalance - v.postBalance);

        require(v.sent <= v.output, "swap/bad-token");
    }

    // @audit-info: normalizes the `value` of the given `tokenn` to 18 decimals
    function scaleFrom(ERC20Like token, uint value) internal returns (uint) {
        uint decimals = token.decimals();

        // for instance, DAI with `18` decimals, 10¹⁸
        if (decimals == 18) {
            return value;
        }
        // for instance, USDC with `6` decimals
        // 10⁶ * 10⁽¹⁸⁻⁻⁶⁾
        else if (decimals < 18) {
            return value * 10 ** (18 - decimals);
        }
        // for instance xTOKEN with `24` decimals
        // (10²⁴ * 10¹⁸) / 10²⁴
        else {
            return (value * 10 ** 18) / 10 ** decimals;
        }
    }

    /// @audit-info: converts a normalized `value` (18 decimals) of a praticular `token` to it's native decimal
    function scaleTo(ERC20Like token, uint value) internal returns (uint) {
        uint decimals = token.decimals();

        // for instance, DAI with `18` decimals, 10¹⁸
        if (decimals == 18) {
            return value;
        }
        // for instance, USDC with `6` decimals
        // (10¹⁸ * 10⁶) / 10¹⁸
        else if (decimals < 18) {
            return (value * 10 ** decimals) / 10 ** 18;
        }
        // for instance xTOKEN with `24` decimals
        // 10¹⁸ * 10⁽²⁴⁻⁻¹⁸⁾
        else {
            return value * 10 ** (decimals - 18);
        }
    }

    // @audit-info: allows owner of LP tokens transfer them to an arbitrary address
    function transfer(address to, uint amount) public returns (bool) {
        require(balances[msg.sender] >= amount, "transfer/low-balance");

        balances[msg.sender] -= amount;
        balances[to] += amount; // @audit-notice: theoretically, this can overflow

        return true;
    }

    // @audit-info: allows transferring LP tokens on-approval of `from` address
    function transferFrom(
        address from,
        address to,
        uint amount
    ) public returns (bool) {
        require(
            approvals[from][msg.sender] >= amount,
            "transferFrom/low-approval"
        );
        require(balances[from] >= amount, "transferFrom/low-balance");

        approvals[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;

        return true;
    }

    // @audit-info: allows an amount of sender's funds to be transfered by arbitrary address
    // @audit-notice: can be front-ran to spend allowance before allowing a new amount
    function approve(address who, uint amount) public returns (bool) {
        approvals[msg.sender][who] = amount;

        return true;
    }

    // @audit-info: returns the amount of `who` tokens the `spender` is allowed to transfer
    function allowance(
        address who,
        address spender
    ) public view returns (uint) {
        return approvals[who][spender];
    }

    // @audit-info: returns the LP tokens balance of an address
    function balanceOf(address who) public returns (uint) {
        return balances[who];
    }

    // @audit-info: returns amount of LP tokens minted (represents collateral in this token)
    function totalSupply() public view returns (uint) {
        return supply;
    }

    // @audit-info: basic decimals of ERC20 LP tokens
    function decimals() public view returns (uint8) {
        return 18;
    }

    // @audit-info: basic name of ERC20 LP tokens
    function name() public view returns (string memory) {
        return "StableSwap v1.0";
    }

    // @audit-info: basic symbol of ERC20 LP tokens
    function symbol() public view returns (string memory) {
        return "USDSWAP";
    }

    // @audit-info: returns the total balance of underlying tokens in this contract - normalized to `18` decimals
    function totalValue() public view returns (uint) {
        uint value = 0;
        for (uint i = 0; i < underlying.length; i++) {
            value += scaleFrom(
                underlying[i], // `token` - DAI | TrueUSD | USDC | USDT
                underlying[i].balanceOf(address(this)) // balanceOf `token` this address holds
            );
        }
        return value;
    }

    // @audit-info: function for owner to add collateral tokens accepted by the pool
    function addCollateral(ERC20Like collateral) public {
        require(msg.sender == owner, "addCollateral/not-owner");

        // @audit-question: not the best setup to have 2 sources of truth... out of sync possible?
        // From the `Setup` contract, underlying tokens are:
        // 1. DAI
        // 2. TrueUSD
        // 3. USDC
        // 4. USDT
        underlying.push(collateral);
        hasUnderlying[address(collateral)] = true;
    }
}
