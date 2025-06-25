// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import "../../src/2021/03.Broker.sol";
import "./03.BrokerExploit.t.sol";

contract Token {
    // MISSING FUNCTIONS
    // name()
    // symbol()
    // decimals()

    // balanceOf() -> uint256
    mapping(address => uint256) public balanceOf;
    // allowance() -> uint256
    mapping(address => mapping(address => uint256)) public allowance;

    // totalSupply() -> uint256
    uint256 public totalSupply = 1_000_000 ether;

    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }

    // approve() -> bool
    function approve(address to, uint256 amount) public returns (bool) {
        allowance[msg.sender][to] = amount;
        return true;
    }

    // transfer() -> bool
    function transfer(address to, uint256 amount) public returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    // transferFrom() -> bool
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        if (from != msg.sender) {
            allowance[from][to] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    // NON-STANDARD ERC20 methods
    // dropped() -> bool
    mapping(address => bool) public dropped;
    uint256 public AMT = totalSupply / 100_000; // 10 ether

    // @audit-notice: this function increses caller's balance and `totalSupply`
    // @audit-info: I'm pretty sure this function will be successfully callable by multiple "whiteHat" addresses
    function airdrop() public {
        require(!dropped[msg.sender], "err: only once");
        dropped[msg.sender] = true;

        balanceOf[msg.sender] += AMT;
        totalSupply += AMT;
    }
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

// https://0xrpc.io/eth
contract SetupBroker is Script {
    using SafeMath for uint256;

    WETH9 public constant weth =
        WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory public constant factory =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    Token public token;
    IUniswapV2Pair public pair;
    Broker public broker;

    uint256 constant DECIMALS = 1 ether;
    uint256 totalBefore;

    address whiteHat = makeAddr("white-hat-1");

    modifier checkIsSolved() {
        _;
        require(_isSolved());
    }

    // create and bootstrap the token/weth pool for borrowing against WETH
    function setUp() public {
        vm.deal(address(this), 50 ether);
        weth.deposit{value: 50 ether}();

        token = new Token();
        pair = IUniswapV2Pair(
            factory.createPair(address(weth), address(token))
        );
        broker = new Broker(pair, ERC20Like(address(token)));
        token.transfer(address(broker), 500_000 * DECIMALS);

        weth.transfer(address(pair), 25 ether);
        token.transfer(address(pair), 500_000 * DECIMALS);
        pair.mint(address(this));

        weth.approve(address(broker), type(uint256).max);
        broker.deposit(25 ether);
        broker.borrow(250_000 * DECIMALS);

        totalBefore =
            weth.balanceOf(address(broker)) +
            token.balanceOf(address(broker)) /
            broker.rate();
    }

    function run() public checkIsSolved {
        vm.startBroadcast(whiteHat);

        BrokerExploit exploit = new BrokerExploit(broker, pair);
        exploit.attack(address(this));

        vm.stopBroadcast();
    }

    function _isSolved() private view returns (bool) {
        return weth.balanceOf(address(broker)) < 5 ether;
    }
}
