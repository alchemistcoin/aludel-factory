import { ethers } from "hardhat";

async function main() {

  // We get the contract to deploy
  const AludelFactory = await ethers.getContractFactory("AludelFactory");
  const factory = await AludelFactory.deploy();
  await factory.deployed();

  const AludelTemplate = await ethers.getContractFactory("AludelTemplate");
  const template = await AludelTemplate.deploy();
  await template.deployed();

  await factory.addTemplate(template.address)

  console.log("AludelFactory deployed to:", factory.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
