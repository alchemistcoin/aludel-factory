import "@nomiclabs/hardhat-ethers";
import { getNamedAccounts } from "hardhat";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { GEYSER_V2_VANITY_ADDRESS } from "../constants";

const deployFunc = async function ({
  ethers,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const { deployer } = await getNamedAccounts();
  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address,
    await ethers.getSigner(deployer)
  );

  log("Adding disabled GeyserV2 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await (
      await factory.addTemplate(GEYSER_V2_VANITY_ADDRESS, "GeyserV2", true)
    ).wait();
  } catch {
    log("WARNING: GeyserV2 was already added");
  }
};

deployFunc.tags = ["GeyserV2Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
