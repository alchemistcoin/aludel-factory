import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("WhitelistHook", {
    from: deployer,
    log: true,
    contract: "src/contracts/aludel/WhitelistHook.sol:WhitelistHook",
    deterministicDeployment: false,
  });
};

deployFunc.tags = ["WhitelistHook"];
export default deployFunc;
