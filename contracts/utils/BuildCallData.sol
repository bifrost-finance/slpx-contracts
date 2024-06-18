// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

library BuildCallData {
    uint8 public constant PALLET_INDEX = 125;
    uint8 public constant MINT_CALL_INDEX = 0;
    uint8 public constant SWAP_CALL_INDEX = 1;
    uint8 public constant REDEEM_CALL_INDEX = 2;
    uint8 public constant STABLE_POOL_SWAP_CALL_INDEX = 3;
    uint8 public constant MINT_WITH_CHANNEL_ID_CALL_INDEX = 13;

    function buildMintCallBytes(
        address caller,
        bytes2 token,
        bytes memory targetChain,
        string memory remark
    ) public pure returns (bytes memory) {
        bytes memory prefix = new bytes(2);
        // storage pallet index
        prefix[0] = bytes1(PALLET_INDEX);
        // storage call index
        prefix[1] = bytes1(MINT_CALL_INDEX);

        // astar target_chain = bytes1(0)
        return
            bytes.concat(
                prefix,
                abi.encodePacked(caller),
                token,
                targetChain,
                toScaleString(remark)
            );
    }

    function buildMintWithChannelIdCallBytes(
        address caller,
        bytes2 token,
        bytes memory targetChain,
        string memory remark,
        uint32 channel_id
    ) public pure returns (bytes memory) {
        bytes memory prefix = new bytes(2);
        // storage pallet index
        prefix[0] = bytes1(PALLET_INDEX);
        // storage call index
        prefix[1] = bytes1(MINT_WITH_CHANNEL_ID_CALL_INDEX);

        // astar target_chain = bytes1(0)
        return
            bytes.concat(
            prefix,
            abi.encodePacked(caller),
            token,
            targetChain,
            toScaleString(remark),
            encode_uint32(channel_id)
        );
    }

    function buildSwapCallBytes(
        address caller,
        bytes2 currency_in,
        bytes2 currency_out,
        uint128 currency_out_min,
        bytes memory targetChain
    ) public pure returns (bytes memory) {
        bytes memory prefix = new bytes(2);
        // storage pallet index
        prefix[0] = bytes1(PALLET_INDEX);
        // storage call index
        prefix[1] = bytes1(SWAP_CALL_INDEX);

        // astar target_chain = bytes1(0)
        return
            bytes.concat(
                prefix,
                abi.encodePacked(caller),
                currency_in,
                currency_out,
                encode_uint128(currency_out_min),
                targetChain
            );
    }

    function buildStablePoolSwapCallBytes(
        address caller,
        uint32 pool_id,
        bytes2 currency_in,
        bytes2 currency_out,
        uint128 min_dy,
        bytes memory targetChain
    ) public pure returns (bytes memory) {
        bytes memory prefix = new bytes(2);
        // storage pallet index
        prefix[0] = bytes1(PALLET_INDEX);
        // storage call index
        prefix[1] = bytes1(STABLE_POOL_SWAP_CALL_INDEX);

        // astar target_chain = bytes1(0)
        return
            bytes.concat(
                prefix,
                abi.encodePacked(caller),
                encode_uint32(pool_id),
                currency_in,
                currency_out,
                encode_uint128(min_dy),
                targetChain
            );
    }

    function buildRedeemCallBytes(
        address caller,
        bytes2 vtoken,
        bytes memory targetChain
    ) public pure returns (bytes memory) {
        bytes memory prefix = new bytes(2);
        // storage pallet index
        prefix[0] = bytes1(PALLET_INDEX);
        // storage call index
        prefix[1] = bytes1(REDEEM_CALL_INDEX);

        // astar target_chain = bytes1(0)
        return
            bytes.concat(prefix, abi.encodePacked(caller), vtoken, targetChain);
    }

    //https://docs.substrate.io/reference/scale-codec/
    function encode_uint128(uint128 x) internal pure returns (bytes memory) {
        bytes memory b = new bytes(16);
        for (uint i = 0; i < 16; i++) {
            b[i] = bytes1(uint8(x / (2 ** (8 * i))));
        }
        return b;
    }

    //https://docs.substrate.io/reference/scale-codec/
    function encode_uint32(uint32 x) internal pure returns (bytes memory) {
        bytes memory b = new bytes(4);
        for (uint i = 0; i < 4; i++) {
            b[i] = bytes1(uint8(x / (2 ** (8 * i))));
        }
        return b;
    }

    //https://docs.substrate.io/reference/scale-codec/
    function toTruncBytes(uint64 x) internal pure returns (bytes memory) {
        bytes memory b = new bytes(8);
        uint len = 0;
        for (uint i = 0; i < 8; i++) {
            uint8 temp = uint8(x / (2 ** (8 * i)));
            if (temp != 0) {
                b[i] = bytes1(temp);
            } else {
                len = i;
                break;
            }
        }
        bytes memory rst = new bytes(len);
        for (uint i = 0; i < len; i++) {
            rst[i] = b[i];
        }
        return rst;
    }

    // Convert an hexadecimal character to their value
    function fromScaleChar(uint8 c) internal pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return 48 + c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("z")) {
            return 97 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("Z")) {
            return 65 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    // encode the string to bytes
    // following the scale format
    // format: len + content
    // a-z: 61->87
    // A-Z: 41->57
    // 0-9: 30->40
    function toScaleString(
        string memory s
    ) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        bytes memory len = toTruncBytes(uint64(ss.length * 4));
        bytes memory content = new bytes(ss.length);
        for (uint i = 0; i < ss.length; ++i) {
            content[i] = bytes1(fromScaleChar(uint8(ss[i])));
        }
        bytes memory rst = bytes.concat(len, content);
        return rst;
    }
}
