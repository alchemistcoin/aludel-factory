import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // deploy factory
  await deploy("RewardPoolFactory", {
    from: deployer,
    log: true,
    contract: "RewardPoolFactory",
    deterministicDeployment: false,
  });
}

module.exports.tags = ["RewardPoolFactory"];
