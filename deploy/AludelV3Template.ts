import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const aludelContract = await get("AludelV3");

  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address
  );

  log("Adding working AludelV3 templates to factory");
  try {
    await (
      await factory.addTemplate(aludelContract.address, "AludelV3", false)
    ).wait();
  } catch {
    log("WARNING: AludelV3 was already added");
  }
};

deployFunc.tags = ["AludelV3Template"];
deployFunc.dependencies = ["AludelFactory", "AludelV3"];
export default deployFunc;
