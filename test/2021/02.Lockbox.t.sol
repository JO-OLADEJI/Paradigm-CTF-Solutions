// SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

import {Entrypoint} from "../../src/2021/02.Lockbox.sol";

contract SetupLockbox {
    Entrypoint public entrypoint;

    modifier checkIsSolved() {
        _;
        _isSolved();
    }

    constructor() public {
        entrypoint = new Entrypoint();
    }

    function test_entrypoint() public checkIsSolved {
        bool success = address(entrypoint).call(
            abi.encodePacked(
                bytes4(keccak256("solve(bytes4)")),
                bytes4(blockhash(block.number - 1)),
                bytes26(0),
                bytes1(0xff),
                uint8(28),
                bytes32(
                    0x370df20998cc15afb44c2879a3c162c92e703fc4194527fb6ccf30532ca1dd3b
                ),
                bytes32(
                    0xca4c0d1d00a7c0126700ff7ec223814d40a01d242c888ea751a592e2336252da
                ),
                bytes32(
                    uint256(
                        0xca4c0d1d00a7c0126700ff7ec223814d40a01d242c888ea751a592e2336252da
                    ) + uint256(0x02)
                ),
                keccak256(abi.encodePacked("choose")),
                bytes32(
                    0x370df20998cc15afb44c2879a3c162c92e703fc4194527fb6ccf30532ca1dd3b
                ),
                bytes32(uint256(0x0a))
            )
        );

        require(success);
    }

    function _isSolved() private view returns (bool) {
        return entrypoint.solved();
    }
}
