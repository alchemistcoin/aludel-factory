import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const recipient = deployer;
  const bps = 100;

  // deploy factory
  await deploy("AludelFactory", {
    from: deployer,
    args: [recipient, bps],
    log: true,
    contract: "AludelFactory",
    deterministicDeployment: false,
  });
};
deployFunc.tags = ["AludelFactory"];
deployFunc.skip = async function skip({
  deployments,
}: HardhatRuntimeEnvironment) {
  // We want to keep the existing AludelFactory if there's already one
  // deployed, since it's the root of trust for the frontend and it permissions
  // Aludel templates, differences in deployed bytecode be damned.
  if (await deployments.getOrNull("AludelFactory")) {
    return true;
  } else {
    return false;
  }
};
export default deployFunc;
