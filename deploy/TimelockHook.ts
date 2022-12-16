import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("TimelockHook", {
    from: deployer,
    args: [],
    log: true,
    contract: "src/contracts/aludel/TimelockHook.sol:TimelockHook",
    deterministicDeployment: false,
  });
};

deployFunc.tags = ["TimelockHook"];
export default deployFunc;
