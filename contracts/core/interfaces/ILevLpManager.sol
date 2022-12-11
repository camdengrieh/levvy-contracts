// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ILevLpManager {
    function usdl() external view returns (address);

    function cooldownDuration() external returns (uint256);

    function getAumInUsdl(bool maximise) external view returns (uint256);

    function lastAddedAt(address _account) external returns (uint256);

    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLevLp) external returns (uint256);

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdl,
        uint256 _minLevLp
    ) external returns (uint256);

    function removeLiquidity(address _tokenOut, uint256 _levLpAmount, uint256 _minOut, address _receiver) external returns (uint256);

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _levLpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function setShortsTrackerAveragePriceWeight(uint256 _shortsTrackerAveragePriceWeight) external;

    function setCooldownDuration(uint256 _cooldownDuration) external;
}
