import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = function ({ deployments }: HardhatRuntimeEnvironment) {
  deployments.log("running virtual task to configure all templates");
};

deployFunc.tags = ["templates"];
deployFunc.dependencies = [
  "GeyserV2Template",
  "AludelV2Template",
  "AludelV1Template",
];
export default deployFunc;
