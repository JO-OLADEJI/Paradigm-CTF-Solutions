// SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

// import {Test} from "forge-std/Test.sol";
import {Entrypoint} from "../../src/2021/02.Lockbox.sol";

contract SetupLockbox {
    Entrypoint public entrypoint;

    constructor() public {
        entrypoint = new Entrypoint();
    }

    function isSolved() public view returns (bool) {
        return entrypoint.solved();
    }
}
