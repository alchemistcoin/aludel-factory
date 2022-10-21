import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  GEYSER_V2_VANITY_ADDRESS,
  ALUDEL_V1_VANITY_ADDRESS,
  preExistingPrograms,
} from "../constants";

const deployFunc = async function ({
  getChainId,
  deployments,
  ethers,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;
  const chainId: string = await getChainId();
  const programsToAdd = preExistingPrograms[chainId];

  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address
  );
  const aludelV2Deployment = await get("AludelV2");

  for (const item of programsToAdd) {
    const { name, templateName, program, stakingTokenUrl } = item;
    log(`adding pre-existing program ${name}`);

    try {
      await factory.addProgram(
        program,
        getTemplateAddress(templateName),
        name,
        stakingTokenUrl,
        0
      );
    } catch {
      log(`WARNING: couldnt add program ${name} at ${program}`);
    }
  }

  function getTemplateAddress(templateName: string): string {
    if (templateName == "GeyserV2") {
      return GEYSER_V2_VANITY_ADDRESS;
    } else if (templateName == "AludelV1") {
      return ALUDEL_V1_VANITY_ADDRESS;
    } else if (templateName == "AludelV2") {
      return aludelV2Deployment.address;
    } else {
      throw new Error(`Invalid template name ${templateName}`);
    }
  }
};

deployFunc.tags = ["programs"];
// AludelFactory is a bit redundant since it's also a dependency for templates
deployFunc.dependencies = ["templates", "AludelFactory", "AludelV2"];
export default deployFunc;
