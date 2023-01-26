import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ALUDEL_V1_VANITY_ADDRESS } from "../constants";

const deployFunc = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployedFactory = await get("AludelFactory");
  const factory = (
    await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
  ).connect(await ethers.getSigner(deployer));

  log("Adding disabled AludelV1 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await (
      await factory.addTemplate(ALUDEL_V1_VANITY_ADDRESS, "AludelV1", true)
    ).wait();
  } catch (err) {
    // cast sig 'TemplateAlreadyAdded()'
    if (err.data === "0xf298693e") {
      log("WARNING: AludelV1 was already added");
    } else {
      throw err;
    }
  }
};

deployFunc.tags = ["AludelV1Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
