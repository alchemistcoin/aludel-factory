import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const aludelContract = await get("AludelV2");

  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address
  );

  log("Adding working AludelV2 templates to factory");
  try {
    await (
      await factory.addTemplate(aludelContract.address, "AludelV2", false)
    ).wait();
  } catch {
    log("WARNING: GeyserV2 was already added");
  }
};

deployFunc.tags = ["AludelV2Template"];
deployFunc.dependencies = ["AludelFactory", "AludelV2"];
export default deployFunc;
