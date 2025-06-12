// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {Test} from "forge-std/Test.sol";
import {Hello} from "../../src/2021/01.Hello.sol";

contract SetupHello is Test {
    Hello public hello;

    modifier checkIsSolved() {
        _;
        _isSolved();
    }

    constructor() {
        hello = new Hello();
    }

    function test_hello() public checkIsSolved {
        hello.solve();
    }

    function _isSolved() private view {
        assert(hello.solved());
    }
}
