import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("PowerSwitchFactory", {
    from: deployer,
    args: [],
    log: true,
    contract: "PowerSwitchFactory",
    deterministicDeployment: false,
  });
}
module.exports.tags = ["PowerSwitchFactory"];
