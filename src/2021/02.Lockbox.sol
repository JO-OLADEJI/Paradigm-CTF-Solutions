// SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

contract Stage {
    Stage public next; // slot: 0x00

    /**
     * storage layout of this contract:
     * 0x00: [empty-12-bytes] [address(next)-20-bytes]
     */
    constructor(Stage next_) public {
        next = next_;
    }

    function getSelector() public view returns (bytes4);

    modifier _() {
        _;

        assembly {
            let next := sload(next_slot)

            // returns 0 if `next` does not contain an address. (i.e if it's empty)
            if iszero(next) {
                return(0, 0)
            }

            // store `bytes4(keccak256("getSelector()"))` in mem:0x00
            mstore(
                0x00,
                0x034899bc00000000000000000000000000000000000000000000000000000000
            )

            // this call removes the `success` state of this call from the stack
            pop(
                // @audit-info: basically, this `call()` calls `getSelector()` on the address stored in the `next` state variable and places the return value (bytes4) in the memory starting from location 0x00 up to but not including 0x04
                call(
                    gas(), // gas to pass to called contract
                    next, // address to call
                    0, // msg.value
                    0, // memory offset of where calldata starts
                    0x04, // memory size of calldata. it's 4 so the calldata is `bytes4(keccak256("getSelector()"))`
                    0x00, // memory offset of where to store return data
                    0x04 // size of return data to copy - @audit-notice: this overwrites the `bytes4(keccak256("getSelector()"))` previously stored in memory location `0x00`
                )
            )

            // copy original call's calldata parameters (cause it excludes the selector) to memory
            calldatacopy(
                0x04, // memory offset to write the calldata
                0x04, // calldata offset where copying start from
                sub(calldatasize(), 0x04) // @audit-notice: size to copy: this is actually the length of the arguments (calldatasize - selector size)
            )

            // @audit-notice: this call is kind of tricky; what it does is that it passes the calldata of the initial function call made to this contract, but calls another function with it. the function being called is the one whose' selector is returned by the earlier `getSelector()` call
            switch call(
                gas(), // gas passed to called contract :/
                next, // @audit-notice: address to call; same as the address called earlier, but we're (hopefully) calling another function from the contract provided the `getSelector()` returned a different function selector other than `bytes4(keccak256("getSelector()"))`
                0, // msg.value
                0, // memory offset where calldata starts
                calldatasize(), // size of calldata made to this function.
                0, // memory offset of where to store return data
                0 // size of return data to copy
            )
            // handles the case of a `revert`
            case 0 {
                // @audit-notice: this has the potential to overwrite the previous call's calldata from memory. memory at this point is messy, so proceed carefully
                // copies data returned by the last sub-content: i.e the last `call()` above
                returndatacopy(
                    0x00, // memory offset where overwrite begins
                    0x00, // return data offset where copy begins
                    returndatasize() // size of data to copy :/
                )

                // reverts this call entirely, passing some data as it's "reason"
                revert(
                    0x00, // memory offset where revert's "reason" starts from
                    returndatasize() // size of memory parsed as "reason"
                )
            }
            // handles the case of a successful execution
            case 1 {
                // @audit-notice: this has the potential to overwrite the previous call's calldata from memory. memory at this point is messy, so proceed carefully
                // copies data returned by the last sub-content: i.e the last `call()` above
                returndatacopy(
                    0x00, // memory offset where overwrite begins
                    0x00, // return data offset where copy begins
                    returndatasize() // size of data to copy :/
                )

                // @audit-info: because the `_` modifier potentially modifies the blockchain state with it's calls, this can only be accessed by an on-chain function.
                // returns the data copied from the return data above. everyone's happy :)... hopefully
                return(
                    0x00, // memory offset where returned data starts from
                    returndatasize() // size of memory to return
                )
            }
        }
    }
}

// @audit-notice: this contract is trying to be confusing....
contract Entrypoint is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(new Stage1())`
    /**
     * storage layout of this contract:
     * 0x00: [empty-11-bytes] [bool(solved)-1-byte] [address(next)-20-bytes]
     */
    constructor() public Stage(new Stage1()) {}

    // returns `bytes4(keccak256("solve(bytes4)"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    bool public solved; // slot: 0x00, 0ffset: 0x14

    function solve(bytes4 guess) public _ {
        // for this function to execute successfully, the `guess` has to equal the first 4 bytes of the previous block's blockhash.
        // if not, it reverts with the message "do you feel lucky?" :/
        require(
            guess ==
                bytes4(
                    // according to the docs: "hash of the given block when `blocknumber`(argument) is one of the 256 most recent blocks; otherwise returns zero"
                    blockhash(block.number - 1)
                ),
            "do you feel lucky?"
        );

        // once the require above passes, it sets `solved` to true.
        solved = true;

        // @audit-notice: do not forget the `_` modifier in the function definition above. what this means is that the whole low-level code defined in `Stage` is executed, calling into `address(next -> new Stage1())` below.
    }
}

contract Stage1 is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(new Stage2())`
    /**
     * storage layout of this contract:
     * 0x00: [empty-12-bytes] [address(next)-20-bytes]
     */
    constructor() public Stage(new Stage2()) {}

    // returns `bytes4(keccak256("solve(uint8,bytes32,bytes32)"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    function solve(uint8 v, bytes32 r, bytes32 s) public _ {
        // for this function to execute successfully, the signer of the "stage1" message has to be `0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf`
        // if not, it reverts with the message "who are you?" :/
        require(
            // @audit-info: `ecrecover(bytes32, uint8, bytes32, bytes32)` is a precompiled contract in EVM that returns the computed `address` that signed a certain message. The expected `v`, `r`, & `s` are the splitted signature (total of 65 bytes) of the signed 'certain' message. The message in this case is "stage1".
            // possible ways of getting this:
            // 1. etherscan: this contract doesn't protect against replay attacks, so can I find the signature on etherscan and re-use it?
            // 2. brute-force: omg, I use a Macbook pro m3 max that'll take forever to brute-force the private key for the given address
            // 3. blockchain indexing using archive node: start searching for where the address was used with a signature and see if the message hash used is keccak256("stage1"). To be honest, this is not feasible as there's too much data to search through
            // 4. check around if the private key to the address has been leaked or provided to us by paradigm
            ecrecover(keccak256("stage1"), v, r, s) ==
                0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf,
            "who are you?"
        );

        // @audit-notice: do not forget the `_` modifier in the function definition above. what this means is that the whole low-level code defined in `Stage` is executed, calling into `address(next -> new Stage2())` below.
    }
}

contract Stage2 is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(new Stage3())`
    /**
     * storage layout of this contract:
     * 0x00: [empty-12-bytes] [address(next)-20-bytes]
     */
    constructor() public Stage(new Stage3()) {}

    // returns `bytes4(keccak256("solve(uint16,uint16)"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    function solve(uint16 a, uint16 b) public _ {
        // @audit-notice: we kinda have an impossible situation here. How can `a` be greater than 0 and `b` greater than 0 and have `a + b` be less than `a`?? At the very least, `a + b` should be at least `++a` given that both `a` and `b` are integers greater than 0. But it's all a mask, a bug I see right through. Given the solidity version, we know that it's a classic Overflow/Underflow attack vector, and I'll be exploiting it today! :)
        require(a > 0 && b > 0 && a + b < a, "something doesn't add up");

        // @audit-notice: do not forget the `_` modifier in the function definition above. what this means is that the whole low-level code defined in `Stage` is executed, calling into `address(next -> new Stage3())` below.
    }
}

contract Stage3 is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(new Stage4())`
    /**
     * storage layout of this contract:
     * 0x00: [empty-12-bytes] [address(next)-20-bytes]
     */
    constructor() public Stage(new Stage4()) {}

    // returns `bytes4(keccak256("solve(uint256,uint256[4],uint256[4])"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    function solve(
        uint idx,
        uint[4] memory keys,
        uint[4] memory lock
    ) public _ {
        // a very weird condition but given `k` equals `idx` modulo `4`, then `keys[k]` must be equal to `lock[k]`, if not the function will revert with the error messge "keys did not fit lock". I'm currently thinking to just set all values in both arrays to be equal, but I'm sure some more constraints will be introduced below
        // technically, any number modulo x is always less than x -> therefore the below indexes can only be `0`, `1`, `2`, or `3`. it cannot be anything else.
        // `keys[0] === lock[0]` OR
        // `keys[1] === lock[1]` OR
        // `keys[2] === lock[2]` OR
        // `keys[3] === lock[3]`
        require(keys[idx % 4] == lock[idx % 4], "key did not fit lock");

        // @audit-notice: the loop runs when `i` is strictly less than `4 - 1` (keys.length -> (4) - 1). which means the loop runs when `i` is `0`, `1` and `2`. So it's important to know that it runs just 3 times, as opposed to the canonical 4 times (to traverse the whole array)
        for (uint i = 0; i < keys.length - 1; i++) {
            // this requires the items in `keys` array to be in ascending order. failure to attain that condition makes the function revert
            // `keys[0] < keys[0+1 -> 1] === true` AND
            // `keys[1] < keys[1+1 -> 2] === true` AND
            // `keys[2] < keys[2+1 -> 3] === true` AND
            require(keys[i] < keys[i + 1], "out of order");
        }

        // canonical loop that runs 4 times.
        for (uint j = 0; j < keys.length; j++) {
            // technically, any number modulo `2` that equals `0` has to be a multiple of 2, zero inclusive. so it means the difference between `keys[j]` and `lock[j]` has to be a multiple of 2, i.e an even number. The order of the differences also hints that the items in `keys` should be greater than their counterpart in `lock`, else it's possible to run into Overflow/Underflow given the solidity version
            // `(keys[0] - lock[0]) === x` {x: x is a multiple of 2} AND
            // `(keys[1] - lock[1]) === x` {x: x is a multiple of 2} AND
            // `(keys[2] - lock[2]) === x` {x: x is a multiple of 2} AND
            // `(keys[3] - lock[3]) === x` {x: x is a multiple of 2}
            // ps: I like the humor of saying the condition is a bit "odd" when we're focused on even numbers :)
            require((keys[j] - lock[j]) % 2 == 0, "this is a bit odd");
        }

        // @audit-notice: do not forget the `_` modifier in the function definition above. what this means is that the whole low-level code defined in `Stage` is executed, calling into `address(next -> new Stage4())` below.
    }
}

contract Stage4 is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(new Stage5())`
    /**
     * storage layout of this contract:
     * 0x00: [empty-12-bytes] [address(next)-20-bytes]
     */
    constructor() public Stage(new Stage5()) {}

    // returns `bytes4(keccak256("solve(bytes32[6],uint256)"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    function solve(bytes32[6] choices, uint choice) public _ {
        // this requires that a value in the `choices` array has to be equal to `keccak256(abi.encodePacked("choose")`. I'm at liberty to choose the position of the hash in `choices`, but it has to correspond to index `choice` modulo 6. Right now, I'll just say `choices[0]` work, provided `choice` is `0` as well.
        require(
            choices[choice % 6] == keccak256(abi.encodePacked("choose")),
            "wrong choice!"
        );

        // @audit-notice: do not forget the `_` modifier in the function definition above. what this means is that the whole low-level code defined in `Stage` is executed, calling into `address(next -> new Stage5())` below.
    }
}

contract Stage5 is Stage {
    // initializes base contract `Stage`, having the `next` variable resolve to `address(0)`
    /**
     * storage layout of this contract:
     * 0x00: [empty-32-bytes]
     * essentially, this contract does not have any data in it's state
     */
    constructor()
        public
        Stage(
            // @audit-notice: setting the `next` variable to zero actually makes this callback loop initiated by `_` modifier end -> see `if iszero(next) {return(0, 0)}` above.
            Stage(0x00)
        )
    {}

    // returns `bytes4(keccak256("solve()"))`
    function getSelector() public view returns (bytes4) {
        return this.solve.selector;
    }

    function solve() public _ {
        // this condition mandates that the calldata sent to this function must be less than `256`, else it will revert with "a little too long". This should not be too difficult seeing that this function is called in a new subcontext where a lot of the initial calldata has been trimmed down in the stages above
        require(msg.data.length < 256, "a little too long");

        // @audit-notice: do not forget the `_` modifier in the function definition above. this callback loop will actually terminate here since the value of `next` is `address(0)`
    }
}
