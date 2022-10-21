import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ALUDEL_V1_VANITY_ADDRESS } from "../constants";

const deployFunc = async function ({
  ethers,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address
  );

  log("Adding disabled AludelV1 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await factory.addTemplate(ALUDEL_V1_VANITY_ADDRESS, "AludelV1", true);
  } catch {
    log("WARNING: AludelV1 was already added");
  }
};

deployFunc.tags = ["AludelV1Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
