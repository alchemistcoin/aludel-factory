export const GEYSER_V2_VANITY_ADDRESS =
  "0x00000000000000000000000000000000be15efb2";
export const ALUDEL_V1_VANITY_ADDRESS =
  "0x00000000000000000000000000000000a1fde1b1";
export const preExistingPrograms: {
  [key: string]: Array<{
    name: string;
    templateName: string;
    program: string;
    stakingTokenUrl: string;
  }>;
} = {
  1: [
    {
      name: "Aludel v1",
      program: "0xf0D415189949d913264A454F57f4279ad66cB24d",
      templateName: "AludelV1",
      stakingTokenUrl: "http://lp.mist.alchemist.wtf",
    },
    {
      name: "Aludel v1.5",
      program: "0x93c31fc68E613f9A89114f10B38F9fd2EA5de6BC",
      templateName: "AludelV2",
      stakingTokenUrl: "http://lp.mist.alchemist.wtf",
    },
    {
      name: "Pescadero V2",
      program: "0x56eD0272f99eBD903043399A51794f966D72E526",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.sushi.com/add/ETH/0xd46ba6d942050d489dbd938a2c909a5d5039a161",
    },
    {
      name: "Old Faithful V2",
      program: "0x914A766578C2397da969b3ca088e3e757249A435",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://pools.balancer.exchange/#/pool/0x7860e28ebfb8ae052bfe279c07ac5d94c9cd2937",
    },
    {
      name: "Trinity V2",
      program: "0x0ec93391752ef1A06AA2b83D15c3a5814651C891",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://pools.balancer.exchange/#/pool/0xa751a143f8fe0a108800bfb915585e4255c2fe80",
    },
    {
      name: "Beehive V4",
      program: "0x88F12aE68315A89B885A2f1b0610fE2A9E1720B9",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/add/v2/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2/0xD46bA6D942050d489DBd938a2C909A5d5039A161",
    },
    {
      name: "Splendid Pilot (AAVE)",
      program: "0x1Fee4745E70509fBDc718beDf5050F471298c1CE",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.aave.com/#/deposit/0xd46ba6d942050d489dbd938a2c909a5d5039a161-0xd46ba6d942050d489dbd938a2c909a5d5039a1610xb53c1a33016b2dc2ff3653530bff1848a515c8c5",
    },
    {
      name: "NEO",
      program: "0x872b09f22873Dd22A1CB20c7D7120844650D1B9a",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/exchange?outputCurrency=0x06f3c323f0238c72bf35011071f2b5b7f43a054c",
    },
    {
      name: "GEMINI",
      program: "0x1C8c8aF39d69a497943015833E3a7Ae102D1E2BD",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.sushi.com/add/ETH/0x06f3c323f0238c72bf35011071f2b5b7f43a054c",
    },
    {
      name: "Wizard Island",
      program: "0x004BA6820A30A2c7B6458720495fb1eC5b5f7823",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.sushi.com/add/ETH/0x68CFb82Eacb9f198d508B514d898a403c449533E",
    },
    {
      name: "Post LBP Klimate Party",
      program: "0xa4DC59bAE0Ca1A0e52DAC1885199A2Fb53B3ABE3",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://copperlaunch.com/auctions/0x6aa8a7b23f7b3875a966ddcc83d5b675cc9af54b",
    },
    {
      name: "Ohmies get Liquity",
      program: "0x2230ad29920D61A535759678191094b74271f373",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.sushi.com/add/0x383518188C0C6d7730D91b2c03a03C837814a899/0x5f98805A4E8be255a32880FDeC7F6728C6568bA0",
    },
    {
      name: "EcoFi",
      program: "0x56DC5199e6664cBAa63b7897854A2677999132C7",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/swap?outputCurrency=0xc242eb8e4e27eae6a2a728a41201152f19595c83",
    },
    {
      name: "Tempus",
      program: "0x71bCC385406a8A4694Ccc0102f18DfDd59c08d2E",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.balancer.fi/#/pool/0x514f35a92a13bc7093f299af5d8ebb1387e42d6b0002000000000000000000c9",
    },
    {
      name: "Aludel x CVI",
      program: "0xF2301F29344499727bf69F22980ba667194e6D4d",
      templateName: "AludelV2",
      stakingTokenUrl: "https://lp.mist.alchemist.wtf",
    },
    {
      name: "Element V1",
      program: "0x5C20CEfc5161092Fa295a89E34D3B2bfe66e1E79",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.balancer.fi/#/pool/0x77952e11e1ba727ffcea95a0f38ed7da586eebc7000200000000000000000116",
    },
    {
      name: "Substance V1",
      program: "0xc1F5D0b6617D8EFb951384509E759ac216745627",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.balancer.fi/pools#/pool/0xf33a6b68d2f6ae0353746c150757e4c494e02366000200000000000000000117",
    },
    {
      name: "Matter V1",
      program: "0x89CA56d0D79815Eb896e180fc1b5c21FEdf074f7",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/add/v2/ETH/0x13C99770694f07279607A6274F28a28c33086424",
    },
    {
      name: "Essence V1",
      program: "0x3d9246c38c9e8a22d1f4d2742e28ced721897647",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/swap?use=v1&inputCurrency=ETH&outputCurrency=0x13c99770694f07279607a6274f28a28c33086424",
    },
    {
      name: "Cage Keeper",
      program: "0x3718f99751BCF8B1c63e0E7DE788f099dB43d65b",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/swap?outputCurrency=0xf2ef3551c1945a7218fc4ec0a75c9ecfdf012a4f",
    },
    {
      name: "BITS LBP Bonus",
      program: "0x2575Cb3EFBf701220cd4796c2D2a345623ae086d",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://copperlaunch.com/pools/0xbfAEb93b340468Aa3a980E744258b8e137A51900",
    },
    {
      name: "Larp Party",
      program: "0x07498A1202B086066025B48Aa3c2c5cF9e852f56",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/swap?inputCurrency=0xb7b186D6301080BcBB977d186200b1c649b28089&outputCurrency=ETH&chain=mainnet",
    },
    {
      name: "Beehive V5",
      program: "0x5Bc95edc2a05247235dd5D6d1773B8cCB95D083B",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/add/v2/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2/0xD46bA6D942050d489DBd938a2C909A5d5039A161",
    },
    {
      name: "Trinity V3",
      program: "0x13ED22A00576E41B64B686857B484987a3Ad1A3B",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.balancer.fi/#/pool/0xd4e2af4507b6b89333441c0c398edffb40f86f4d0001000000000000000002ab",
    },
  ],
  5: [
    {
      name: "Aludel V1.5",
      program: "0x33c64c46dC69C1bFd40665AB0cE20BdDb0D589Af",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://app.uniswap.org/#/add/v2/0xDb435816E41eADa055750369Bc2662EFbD465D72/ETH",
    },
  ],
  137: [
    {
      name: "MASQATIC",
      program: "0xeE58832B0a4fd753d6E6184C6bfe3E69019E64Ee",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://quickswap.exchange/#/add/0xEe9A352F6aAc4aF1A5B9f467F6a93E0ffBe9Dd35/ETH",
    },
    {
      name: "MASQEREUM",
      program: "0xFF7C0970dBc4b1fbdE29D814EbE1b5c5F3b11142",
      templateName: "AludelV2",
      stakingTokenUrl:
        "https://quickswap.exchange/#/add/0xEe9A352F6aAc4aF1A5B9f467F6a93E0ffBe9Dd35/0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
    },
  ],
  80001: [
    {
      name: "Mumbai",
      program: "0xb8Fe338Aaac09E510b7925bfc77A997F9a63fb15",
      templateName: "AludelV2",
      stakingTokenUrl: "https://app.uniswap.org/#/swap?chain=polygon_mumbai",
    },
  ],
  43114: [
    {
      name: "Crystal Geyser",
      program: "0x26645e8513B1D20aDb729E7114eDfA930D411720",
      templateName: "GeyserV2",
      stakingTokenUrl:
        "https://app.pangolin.exchange/#/add/0x027dbca046ca156de9622cd1e2d907d375e53aa7/0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7",
    },
  ],
  43113: [],
  31337: [],
};
