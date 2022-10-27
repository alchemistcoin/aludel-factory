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
export default deployFunc;
