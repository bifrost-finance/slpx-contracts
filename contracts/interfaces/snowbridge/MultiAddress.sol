// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2023 Snowfork <hello@snowfork.com>
pragma solidity 0.8.10;

contract MultiAddress {
    /// @dev An address for an on-chain account
    struct MultiAddress {
        Kind kind;
        bytes data;
    }

    enum Kind {
        Index,
        Address32,
        Address20
    }

    function isIndex(MultiAddress calldata multiAddress) public pure returns (bool) {
        return multiAddress.kind == Kind.Index;
    }

    function asIndex(MultiAddress calldata multiAddress) public pure returns (uint32) {
        return abi.decode(multiAddress.data, (uint32));
    }

    function isAddress32(MultiAddress calldata multiAddress) public pure returns (bool) {
        return multiAddress.kind == Kind.Address32;
    }

    function asAddress32(MultiAddress calldata multiAddress) public pure returns (bytes32) {
        return bytes32(multiAddress.data);
    }

    function isAddress20(MultiAddress calldata multiAddress) public pure returns (bool) {
        return multiAddress.kind == Kind.Address20;
    }

    function asAddress20(MultiAddress calldata multiAddress) public pure returns (bytes20) {
        return bytes20(multiAddress.data);
    }

    function multiAddressFromUint32(uint32 id) public pure returns (MultiAddress memory) {
        return MultiAddress({kind: Kind.Index, data: abi.encode(id)});
    }

    function multiAddressFromBytes32(bytes32 id) public pure returns (MultiAddress memory) {
        return MultiAddress({kind: Kind.Address32, data: bytes.concat(id)});
    }

    function multiAddressFromBytes20(bytes20 id) public pure returns (MultiAddress memory) {
        return MultiAddress({kind: Kind.Address20, data: bytes.concat(id)});
    }
}