// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

import "./interfaces/XcmTransactorV2.sol";
import "./interfaces/Xtokens.sol";
import "./interfaces/ISlpx.sol";
import "./utils/AddressToAccount.sol";
import "./utils/BuildCallData.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract MoonbeamSlpx is ISlpx, OwnableUpgradeable, PausableUpgradeable {
    address internal constant NATIVE_ASSET_ADDRESS =
        0x0000000000000000000000000000000000000802;
    address internal constant XCM_TRANSACTORV2_ADDRESS =
        0x000000000000000000000000000000000000080D;
    address internal constant XTOKENS =
        0x0000000000000000000000000000000000000804;
    bytes1 internal constant MOONBEAM_CHAIN = 0x01;

    XcmTransactorV2.Multilocation internal xcmTransactorDestination;

    address public BNCAddress;
    uint32 public bifrostParaId;

    enum Operation {
        Mint,
        Redeem,
        ZenlinkSwap,
        StableSwap
    }

    struct AssetInfo {
        bytes2 currencyId;
        uint256 operationalMin;
    }

    struct FeeInfo {
        uint64 transactRequiredWeightAtMost;
        uint256 feeAmount;
        uint64 overallWeight;
    }

    mapping(address => AssetInfo) public addressToAssetInfo;
    mapping(Operation => FeeInfo) public operationToFeeInfo;

    function checkAssetIsExist(
        address assetAddress
    ) internal view returns (bytes2) {
        AssetInfo memory assetInfo = addressToAssetInfo[assetAddress];
        require(assetInfo.operationalMin > 0, "Asset is not exist");
        require(assetInfo.currencyId != bytes2(0), "Invalid asset");
        return assetInfo.currencyId;
    }

    function checkFeeInfo(
        Operation operation
    ) internal view returns (FeeInfo memory) {
        FeeInfo memory feeInfo = operationToFeeInfo[operation];
        require(
            feeInfo.transactRequiredWeightAtMost > 0,
            "Invalid transactRequiredWeightAtMost"
        );
        require(feeInfo.feeAmount > 0, "Invalid feeAmount");
        require(feeInfo.overallWeight > 0, "Invalid overallWeight");
        return feeInfo;
    }

    function initialize(
        address _BNCAddress,
        uint32 _bifrostParaId,
        bytes2 _nativeCurrencyId
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        require(_BNCAddress != address(0), "Invalid address");
        require(
            _bifrostParaId == 2001 || _bifrostParaId == 2030,
            "Invalid bifrostParaId"
        );
        require(
            _nativeCurrencyId == 0x020a || _nativeCurrencyId == 0x0801,
            "Invalid nativeCurrencyId"
        );

        setAssetAddressInfo(_BNCAddress, 0x0001, 1_000_000_000_000);
        setAssetAddressInfo(
            NATIVE_ASSET_ADDRESS,
            _nativeCurrencyId,
            1_000_000_000_000_000_000
        );

        BNCAddress = _BNCAddress;
        bifrostParaId = _bifrostParaId;

        // Init xcmTransactorDestination
        bytes[] memory interior = new bytes[](1);
        // Parachain: 2001/2030
        interior[0] = bytes.concat(hex"00", bytes4(_bifrostParaId));
        xcmTransactorDestination = XcmTransactorV2.Multilocation({
            parents: 1,
            interior: interior
        });
    }

    function setOperationToFeeInfo(
        Operation _operation,
        uint64 _transactRequiredWeightAtMost,
        uint64 _overallWeight,
        uint256 _feeAmount
    ) public onlyOwner {
        require(
            _transactRequiredWeightAtMost <= 10000000000,
            "transactRequiredWeightAtMost too large"
        );
        require(_feeAmount <= 1000000000000, "feeAmount too large");
        require(_overallWeight <= 10000000000, "OverallWeight too large");
        operationToFeeInfo[_operation] = FeeInfo(
            _transactRequiredWeightAtMost,
            _feeAmount,
            _overallWeight
        );
    }

    function setAssetAddressInfo(
        address assetAddress,
        bytes2 currencyId,
        uint256 minimumValue
    ) public onlyOwner {
        require(assetAddress != address(0), "Invalid assetAddress");
        require(minimumValue != 0, "Invalid minimumValue");
        require(currencyId != bytes2(0), "Invalid currencyId");
        AssetInfo storage assetInfo = addressToAssetInfo[assetAddress];
        assetInfo.currencyId = currencyId;
        assetInfo.operationalMin = minimumValue;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function xcmTransferAsset(address assetAddress, uint256 amount) internal {
        require(assetAddress != address(0), "Invalid assetAddress");
        require(
            amount >= addressToAssetInfo[assetAddress].operationalMin,
            "Less than MinimumValue"
        );
        bytes32 publicKey = AddressToAccount.AddressToSubstrateAccount(
            _msgSender()
        );
        Xtokens.Multilocation memory dest_account = getXtokensDestination(
            publicKey
        );
        IERC20 asset = IERC20(assetAddress);
        asset.transferFrom(_msgSender(), address(this), amount);
        Xtokens(XTOKENS).transfer(
            assetAddress,
            amount,
            dest_account,
            type(uint64).max
        );
    }

    function xcmTransferNativeAsset(uint256 amount) internal {
        require(
            amount >= addressToAssetInfo[NATIVE_ASSET_ADDRESS].operationalMin,
            "Less than MinimumValue"
        );
        bytes32 publicKey = AddressToAccount.AddressToSubstrateAccount(
            _msgSender()
        );

        Xtokens.Multilocation memory dest_account = getXtokensDestination(
            publicKey
        );
        Xtokens(XTOKENS).transfer(
            NATIVE_ASSET_ADDRESS,
            amount,
            dest_account,
            type(uint64).max
        );
    }

    function mintVNativeAsset(
        address receiver,
        string memory remark
    ) external payable override whenNotPaused {
        require(bytes(remark).length <= 32, "remark too long");
        bytes2 nativeToken = checkAssetIsExist(NATIVE_ASSET_ADDRESS);
        // xtokens call
        xcmTransferNativeAsset(msg.value);

        // Build bifrost xcm-action mint call data
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildMintCallBytes(
            _msgSender(),
            nativeToken,
            targetChain,
            remark
        );
        // XCM Transact
        FeeInfo memory feeInfo = checkFeeInfo(Operation.Mint);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Mint(
            _msgSender(),
            NATIVE_ASSET_ADDRESS,
            msg.value,
            receiver,
            callData,
            remark
        );
    }

    function mintVAsset(
        address assetAddress,
        uint256 amount,
        address receiver,
        string memory remark
    ) external override whenNotPaused {
        require(bytes(remark).length <= 32, "remark too long");

        bytes2 token = checkAssetIsExist(assetAddress);

        // xtokens call
        xcmTransferAsset(assetAddress, amount);

        // Build bifrost xcm-action mint call data
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildMintCallBytes(
            _msgSender(),
            token,
            targetChain,
            remark
        );
        // XCM Transact
        FeeInfo memory feeInfo = checkFeeInfo(Operation.Mint);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Mint(
            _msgSender(),
            assetAddress,
            amount,
            receiver,
            callData,
            remark
        );
    }

    function mintVNativeAssetWithChannelId(
        address receiver,
        string memory remark,
        uint32 channel_id
    ) external payable override whenNotPaused {
        require(bytes(remark).length <= 32, "remark too long");
        bytes2 nativeToken = checkAssetIsExist(NATIVE_ASSET_ADDRESS);
        // xtokens call
        xcmTransferNativeAsset(msg.value);

        // Build bifrost xcm-action mint call data
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildMintWithChannelIdCallBytes(
            _msgSender(),
            nativeToken,
            targetChain,
            remark,
            channel_id
        );
        // XCM Transact
        FeeInfo memory feeInfo = checkFeeInfo(Operation.Mint);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Mint(
            _msgSender(),
            NATIVE_ASSET_ADDRESS,
            msg.value,
            receiver,
            callData,
            remark
        );
    }

    function mintVAssetWithChannelId(
        address assetAddress,
        uint256 amount,
        address receiver,
        string memory remark,
        uint32 channel_id
    ) external override whenNotPaused {
        require(bytes(remark).length <= 32, "remark too long");

        bytes2 token = checkAssetIsExist(assetAddress);

        // xtokens call
        xcmTransferAsset(assetAddress, amount);

        // Build bifrost xcm-action mint call data
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildMintWithChannelIdCallBytes(
            _msgSender(),
            token,
            targetChain,
            remark,
            channel_id
        );
        // XCM Transact
        FeeInfo memory feeInfo = checkFeeInfo(Operation.Mint);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Mint(
            _msgSender(),
            assetAddress,
            amount,
            receiver,
            callData,
            remark
        );
    }

    function redeemAsset(
        address vAssetAddress,
        uint256 amount,
        address receiver
    ) external override whenNotPaused {
        bytes2 vtoken = checkAssetIsExist(vAssetAddress);

        // xtokens call
        xcmTransferAsset(vAssetAddress, amount);

        // xcm transactor call
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildRedeemCallBytes(
            _msgSender(),
            vtoken,
            targetChain
        );
        FeeInfo memory feeInfo = checkFeeInfo(Operation.Redeem);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Redeem(_msgSender(), vAssetAddress, amount, receiver, callData);
    }

    function stablePoolSwap(
        uint32 poolId,
        address assetInAddress,
        address assetOutAddress,
        uint256 assetInAmount,
        uint128 minDy,
        address receiver
    ) external override whenNotPaused {
        bytes2 assetIn = checkAssetIsExist(assetInAddress);
        bytes2 assetOut = checkAssetIsExist(assetOutAddress);

        xcmTransferAsset(assetInAddress, assetInAmount);

        // xcm transactor call
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildStablePoolSwapCallBytes(
            _msgSender(),
            poolId,
            assetIn,
            assetOut,
            minDy,
            targetChain
        );
        FeeInfo memory feeInfo = checkFeeInfo(Operation.StableSwap);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit StablePoolSwap(
            _msgSender(),
            poolId,
            assetInAddress,
            assetOutAddress,
            assetInAmount,
            minDy,
            receiver,
            callData
        );
    }

    function swapAssetsForExactAssets(
        address assetInAddress,
        address assetOutAddress,
        uint256 assetInAmount,
        uint128 assetOutMin,
        address receiver
    ) external override whenNotPaused {
        bytes2 assetIn = checkAssetIsExist(assetInAddress);
        bytes2 assetOut = checkAssetIsExist(assetOutAddress);

        xcmTransferAsset(assetInAddress, assetInAmount);

        // xcm transactor call
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildSwapCallBytes(
            _msgSender(),
            assetIn,
            assetOut,
            assetOutMin,
            targetChain
        );
        FeeInfo memory feeInfo = checkFeeInfo(Operation.ZenlinkSwap);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Swap(
            _msgSender(),
            assetInAddress,
            assetOutAddress,
            assetInAmount,
            assetOutMin,
            receiver,
            callData
        );
    }

    function swapAssetsForExactNativeAssets(
        address assetInAddress,
        uint256 assetInAmount,
        uint128 assetOutMin,
        address receiver
    ) external override whenNotPaused {
        bytes2 assetIn = checkAssetIsExist(assetInAddress);
        bytes2 nativeToken = checkAssetIsExist(NATIVE_ASSET_ADDRESS);

        xcmTransferAsset(assetInAddress, assetInAmount);

        // xcm transactor call
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildSwapCallBytes(
            _msgSender(),
            assetIn,
            nativeToken,
            assetOutMin,
            targetChain
        );
        FeeInfo memory feeInfo = checkFeeInfo(Operation.ZenlinkSwap);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Swap(
            _msgSender(),
            assetInAddress,
            NATIVE_ASSET_ADDRESS,
            assetInAmount,
            assetOutMin,
            receiver,
            callData
        );
    }

    function swapNativeAssetsForExactAssets(
        address assetOutAddress,
        uint128 assetOutMin,
        address receiver
    ) external payable override whenNotPaused {
        bytes2 assetOut = checkAssetIsExist(assetOutAddress);
        bytes2 nativeToken = checkAssetIsExist(NATIVE_ASSET_ADDRESS);

        xcmTransferNativeAsset(msg.value);

        // xcm transactor call
        bytes memory targetChain = abi.encodePacked(MOONBEAM_CHAIN, receiver);
        bytes memory callData = BuildCallData.buildSwapCallBytes(
            _msgSender(),
            nativeToken,
            assetOut,
            assetOutMin,
            targetChain
        );
        FeeInfo memory feeInfo = checkFeeInfo(Operation.ZenlinkSwap);
        XcmTransactorV2(XCM_TRANSACTORV2_ADDRESS).transactThroughSigned(
            xcmTransactorDestination,
            BNCAddress,
            feeInfo.transactRequiredWeightAtMost,
            callData,
            feeInfo.feeAmount,
            feeInfo.overallWeight
        );
        emit Swap(
            _msgSender(),
            NATIVE_ASSET_ADDRESS,
            assetOutAddress,
            msg.value,
            assetOutMin,
            receiver,
            callData
        );
    }

    function getXtokensDestination(
        bytes32 publicKey
    ) internal view returns (Xtokens.Multilocation memory) {
        bytes[] memory interior = new bytes[](2);
        // Parachain: 2001/2030
        interior[0] = bytes.concat(hex"00", bytes4(bifrostParaId));
        // AccountId32: { id: public_key , network: any }
        interior[1] = bytes.concat(hex"01", publicKey, hex"00");
        Xtokens.Multilocation memory dest = Xtokens.Multilocation({
            parents: 1,
            interior: interior
        });

        return dest;
    }
}
