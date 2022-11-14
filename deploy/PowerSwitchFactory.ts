import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("PowerSwitchFactory", {
    from: deployer,
    args: [],
    log: true,
    contract:
      "src/contracts/powerSwitch/PowerSwitchFactory.sol:PowerSwitchFactory",
    deterministicDeployment: false,
  });
};
deployFunc.tags = ["PowerSwitchFactory"];
export default deployFunc;
