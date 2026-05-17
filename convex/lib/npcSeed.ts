// 20 只 NPC 鸵鸟 + 主人资料，seedNPCs mutation 一次性写入 db。
//
// 设计：
//   - 覆盖 16 个 archetype 各 1 只 + 4 只额外（有趣组合）
//   - 主人 bio 是 1-2 句中文简介，让相遇 LLM 拿到可信背景
//   - currentLocation 留给 seedNPCs 在涩谷站 5km 内随机分配（不在这里硬编码）
//
// 字段对齐 schema:
//   - users: { name, mbti, zodiac, bio, isNPC: true }
//   - ostriches: { name, eggType, isNPC: true, personality: {archetype, ...} }

export interface NPCSeed {
  /** 鸵鸟名（用户给鸵鸟起的名）*/
  ostrichName: string;
  /** 1..16 */
  eggType: number;
  /** 内部 archetype 代号，必须跟 personality.archetype 对齐 */
  archetype: string;
  userName: string;
  userMbti: string;
  userZodiac: string;
  /** 1-2 句中文，feed 进相遇 prompt 的"对方主人是谁" */
  userBio: string;
}

export const NPC_SEEDS: ReadonlyArray<NPCSeed> = [
  {
    ostrichName: "石头",
    eggType: 1, archetype: "STEADFAST",
    userName: "陈守一", userMbti: "ISTJ", userZodiac: "金牛座",
    userBio: "33 岁，做老房改造的木匠，从京都搬来涩谷三年。沉默寡言，每天清晨去同一家咖啡馆点同一杯黑咖啡。",
  },
  {
    ostrichName: "墨墨",
    eggType: 2, archetype: "POET",
    userName: "宋晓予", userMbti: "INFP", userZodiac: "双鱼座",
    userBio: "27 岁独立杂志编辑，京都搬来涩谷做了本叫《周日的雨》的小刊。爱在代代木公园写东西。",
  },
  {
    ostrichName: "大白",
    eggType: 3, archetype: "STRAIGHTSHOOTER",
    userName: "张大胆", userMbti: "ESTP", userZodiac: "白羊座",
    userBio: "29 岁，开了家奶茶店在道玄坂。说话直，从不绕弯子，被员工又爱又恨。",
  },
  {
    ostrichName: "团子",
    eggType: 4, archetype: "CUDDLER",
    userName: "林糖糖", userMbti: "INFP", userZodiac: "巨蟹座",
    userBio: "24 岁烘焙学徒，爱穿粉色，宫下公园樱花季每天都去打卡。说话叠词多，遇事先哭再笑。",
  },
  {
    ostrichName: "老周",
    eggType: 5, archetype: "WORLDLY",
    userName: "周大叔", userMbti: "ESFP", userZodiac: "射手座",
    userBio: "48 岁开了 20 年居酒屋，在涩谷横丁。见过无数客人，记得每个回头客的酒量。",
  },
  {
    ostrichName: "野猫",
    eggType: 6, archetype: "MAVERICK",
    userName: "李野", userMbti: "ENTP", userZodiac: "水瓶座",
    userBio: "26 岁，前广告公司辞职做 NFT 数字艺术家。住宫下公园附近，每天换不同的咖啡馆办公。",
  },
  {
    ostrichName: "默",
    eggType: 7, archetype: "STOIC",
    userName: "霍知行", userMbti: "INTJ", userZodiac: "天蝎座",
    userBio: "35 岁哲学博士在读，在表参道的旧书店打工。一周说不到 50 句话，但读过的书够开个小图书馆。",
  },
  {
    ostrichName: "影子",
    eggType: 8, archetype: "WATCHER",
    userName: "苏倦", userMbti: "INFJ", userZodiac: "处女座",
    userBio: "31 岁心理咨询师，工作室在涩谷站附近。话不多但能在 5 分钟里看出来访者真正烦的事。",
  },
  {
    ostrichName: "团子姐",
    eggType: 9, archetype: "HEDONIST",
    userName: "王嘴馋", userMbti: "ESFJ", userZodiac: "金牛座",
    userBio: "28 岁专栏美食家，专写涩谷小店，被《东京时报》挖去做美食专版。胖了 10 斤但不悔。",
  },
  {
    ostrichName: "か",
    eggType: 10, archetype: "INNOCENT",
    userName: "小满", userMbti: "ENFP", userZodiac: "双子座",
    userBio: "22 岁动画专业大四学生，第一次自己住涩谷出租屋。什么都觉得新奇，连下水道盖子都要拍照。",
  },
  {
    ostrichName: "猛男",
    eggType: 11, archetype: "PROTECTOR",
    userName: "赵勇", userMbti: "ESTJ", userZodiac: "狮子座",
    userBio: "38 岁前柔道馆教练，开了家拳击俱乐部。看到弱势必出头，朋友圈里出了名的护短。",
  },
  {
    ostrichName: "爷",
    eggType: 12, archetype: "ELDER",
    userName: "山田太一", userMbti: "ISFP", userZodiac: "摩羯座",
    userBio: "67 岁退休油画家，独居涩谷老公寓。每周三去明治神宫散步，能跟陌生人聊战后的事一聊两小时。",
  },
  {
    ostrichName: "卦卦",
    eggType: 13, archetype: "MYSTIC",
    userName: "夜璃", userMbti: "INFJ", userZodiac: "天蝎座",
    userBio: "29 岁塔罗师，工作室藏在原宿小巷深处。预约要等三个月，常说「宇宙没让你急」。",
  },
  {
    ostrichName: "脑壳",
    eggType: 14, archetype: "RATIONALIST",
    userName: "Kenji", userMbti: "INTP", userZodiac: "处女座",
    userBio: "30 岁机器学习工程师，在涩谷的 AI 创业公司。说话先列 1234，但晚上偷偷写诗。",
  },
  {
    ostrichName: "夜",
    eggType: 15, archetype: "NIGHTOWL",
    userName: "阿曜", userMbti: "INFP", userZodiac: "巨蟹座",
    userBio: "25 岁电台 DJ，做凌晨 2 点到 5 点的失眠陪伴节目《夜空仍在》。涩谷站凌晨的便利店是她办公室。",
  },
  {
    ostrichName: "向日",
    eggType: 16, archetype: "SUNSHINE",
    userName: "Sunny", userMbti: "ENFJ", userZodiac: "狮子座",
    userBio: "26 岁瑜伽老师，免费给商场员工上午休班课。化妆课老师，化解任何尴尬只需 5 秒。",
  },

  // 4 个有趣组合（archetype 复用但人格、年龄、场景不同）
  {
    ostrichName: "拾光",
    eggType: 2, archetype: "POET",
    userName: "陆鸣", userMbti: "ISFP", userZodiac: "天秤座",
    userBio: "32 岁古董相机修理师，工作室在 SHIBUYA 109 后巷。每天用 1959 年的 Leica 拍一张街景。",
  },
  {
    ostrichName: "小石",
    eggType: 10, archetype: "INNOCENT",
    userName: "圆圆", userMbti: "ESFP", userZodiac: "白羊座",
    userBio: "6 岁，跟妈妈搬到涩谷半年。最爱事情是看井盖花纹。妈妈给她注册的账号。",
  },
  {
    ostrichName: "黑桃",
    eggType: 7, archetype: "STOIC",
    userName: "黎沉", userMbti: "INTJ", userZodiac: "摩羯座",
    userBio: "41 岁神经外科医生，下班才来涩谷喝威士忌。点单只说一个词，但会给隔壁哭的姑娘买一杯。",
  },
  {
    ostrichName: "茶",
    eggType: 12, archetype: "ELDER",
    userName: "千鹤婆婆", userMbti: "ISFJ", userZodiac: "巨蟹座",
    userBio: "72 岁，老公二十年前去世。独自经营涩谷老茶馆。能记得每个客人点过什么茶配什么糕。",
  },
];
