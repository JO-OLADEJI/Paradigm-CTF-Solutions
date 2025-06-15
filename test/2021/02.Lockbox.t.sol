// SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

// import {Test} from "forge-std/Test.sol";
import {Entrypoint} from "../../src/2021/02.Lockbox.sol";

contract SetupLockbox {
    Entrypoint public entrypoint;

    constructor() public {
        entrypoint = new Entrypoint();
    }

    function test_entrypoint() public {
        bytes4 guess = bytes4(blockhash(block.number - 1));
        bool success = address(entrypoint).call(
            abi.encodePacked(
                bytes4(keccak256("solve(bytes4)")),
                guess,
                bytes26(0),
                bytes1(0xff), // stage 2 - uint16(a.1)
                // stage 1 -> v, r, s
                uint8(27),
                bytes32(
                    0x370df20998cc15afb44c2879a3c162c92e703fc4194527fb6ccf30532ca1dd3b
                ),
                bytes32(
                    0x35b3f2e2ff583fed98ff00813ddc7eb17a0ebfc282c011946e2ccbaa9cd3ee67
                )
                // stage 3 - currently stuck here
            )
        );

        require(success);
    }

    function isSolved() public view returns (bool) {
        return entrypoint.solved();
    }
}
