import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const aludelContract = await get("AludelV3");

  const deployedFactory = await get("AludelFactory");
  const factory = (
    await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
  ).connect(await ethers.getSigner(deployer));

  log("Adding working AludelV3 templates to factory");
  try {
    await (
      await factory.addTemplate(aludelContract.address, "AludelV3", false)
    ).wait();
  } catch (err) {
    // cast sig 'TemplateAlreadyAdded()'
    if (err.data === "0xf298693e") {
      log("WARNING: AludelV3 was already added");
    } else {
      throw err;
    }
  }
};

deployFunc.tags = ["AludelV3Template"];
deployFunc.dependencies = ["AludelFactory", "AludelV3"];
export default deployFunc;
