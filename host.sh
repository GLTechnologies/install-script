#!/bin/bash

set -e

# ====== 配置参数 ======
HOSTNAME=$(hostname -I | awk '{print $1}')
# 配置 RTC
Time_threshold=5

# Harbor
while true; do
    read -p "请输入 Harbor 域名或 IP (例如 harbor.example.com 或 192.168.1.1): " HARBOR_DOMAIN

    # 如果为空，不允许
    if [ -z "$HARBOR_DOMAIN" ]; then
        echo "❌ 输入为空，请重新输入。"
        continue
    fi

    # 二次确认
    while true; do
        read -p "你输入的是 [$HARBOR_DOMAIN]，是否确认？(y/n): " yn
        case $yn in
            [Yy] )
                echo "✔ Harbor 域名已确认：$HARBOR_DOMAIN"
                break 2   # 跳出两层循环
                ;;
            [Nn] )
                echo "❗ 请重新输入 Harbor 域名。"
                break     # 仅跳出确认循环，继续重新输入
                ;;
            * )
                echo "⚠ 输入无效，请按 y 或 n。"
                ;;
        esac
    done
done

# ================== 主流程 ==================
main() {
    check_rtc
    install_docker

    sudo apt install -y nano
    
    install_nodejs

    echo "重启 docker 中，请耐心等待..."
    sudo systemctl restart docker
    echo "docker 重启成功"

    #echo "查看日志：sudo docker logs -f harbor-webhook"
    #echo "查看镜像端口："
    #echo "${HOSTNAME}/db"
    #echo "${HOSTNAME}/db?name="
    #echo "设置镜像端口（POST：1024-60000）："
    #echo "${HOSTNAME}/db"
}
# ================== 函数区 ===================
check_rtc() {
    # 获取系统时间戳
    sys_ts=$(date +%s)
    echo "系统时间: ${sys_ts} 秒"

    # 获取 RTC 时间戳
    rtc_ts=$(date -d "$(timedatectl | grep "RTC time" | awk -F': ' '{print $2}')" +%s)
    echo "RTC时间: ${rtc_ts} 秒"

    # 计算差值
    diff=$(( sys_ts - rtc_ts ))
    abs_diff=${diff#-}

    echo "差值: ${abs_diff} 秒"

    # 判断差值是否过大
    if [ "$abs_diff" -gt "$Time_threshold" ]; then
        while true; do
            read -p "时间差过大，是否将系统时间同步为 RTC 时间？(y/n): " yn
            case $yn in
                [Yy] ) 
                    echo "正在同步系统时间..."
                    sudo date -s "@$rtc_ts"
                    echo "同步完成！"
                    break
                    ;;
                [Nn] )
                    echo "已取消同步。"
                    break
                    ;;
                * )
                    echo "输入无效，请输入 y 或 n。"
                    ;;
            esac
        done
    else
        echo "时间差正常。"
    fi
}

install_docker() {
    echo "==== 检查 Docker 是否已安装 ===="

    if command -v docker &> /dev/null; then
        echo "Docker 已安装。"
        return
    fi

    echo "Docker 未安装，开始安装..."

    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose

    sudo systemctl enable docker
    sudo systemctl start docker

    echo "Docker 安装完成。"
}
# ---------------------------------------------------------------
install_nodejs() {
    sudo mkdir -p harbor-webhook
    
    # 写入 .env（关键）
    sudo tee harbor-webhook/.env <<EOF
HARBOR_DOMAIN=$HARBOR_DOMAIN
EOF

    # 添加 Harbor 配置
    sudo mkdir -p /etc/docker
    # daemon.json
    sudo tee /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["$HARBOR_DOMAIN"]
}
EOF

    # app.js
    sudo tee harbor-webhook/app.js > /dev/null <<'EOF'
const express = require("express");
const { exec, execSync } = require("child_process");
const fs = require("fs");
const app = express();

// 环境变量读取
const HARBOR_DOMAIN = process.env.HARBOR_DOMAIN;

if (!HARBOR_DOMAIN) {
  console.error("❌ ERROR: HARBOR_DOMAIN 未设置");
  process.exit(1);
}

app.use(express.json());

// ======================= 端口管理 ==========================
// 数据库存放在容器内部，不再使用 /var/lib
const PORT_DB = "/app/service_ports.db";

//const FIXED_PORTS = {
//    "mysql": 3306,
//    "ruoyi-admin": 8080,
//};
const FIXED_PORTS = {};

const AUTO_PORT_START = 10000;
let saving = false;
// 允许修改的端口范围
const PORT_MIN = 1024;
const PORT_MAX = 60000;

// 确保 DB 文件存在
if (!fs.existsSync(PORT_DB)) {
    fs.writeFileSync(PORT_DB, "");
}

function loadPortDB() {
    let map = {};
    const lines = fs.readFileSync(PORT_DB, "utf8").split("\n");
    lines.forEach(line => {
        if (line.includes("=")) {
            const [name, port] = line.split("=");
            map[name] = parseInt(port);
        }
    });
    return map;
}

async function savePortDB(map) {
    let waited = 0;

    while (saving) {
        if (waited > 10000) {   // 10 秒
            console.warn("⚠ savePortDB 等待锁超时，强制解锁");
            saving = false;
            break;
        }
        await new Promise(r => setTimeout(r, 50));
        waited += 50;
    }

    saving = true;

    try {
        let content = "";
        for (let name in map) content += `${name}=${map[name]}\n`;
        fs.writeFileSync(PORT_DB, content);
    } catch (err) {
        console.error("写入错误:", err);
    } finally {
        saving = false;
    }
}

function allocatePort(serviceName) {
    let db = loadPortDB();

    if (db[serviceName]) return db[serviceName];
    if (FIXED_PORTS[serviceName]) {
        db[serviceName] = FIXED_PORTS[serviceName];
        savePortDB(db);
        return db[serviceName];
    }

    let used = Object.values(db);
    let port = AUTO_PORT_START;
    while (used.includes(port)) port++;

    db[serviceName] = port;
    savePortDB(db);
    return port;
}

// ======================= Webhook ==========================
// GET
app.get("/db", (req, res) => {
    const name = req.query.name;
    const map = loadPortDB();

    if (name) {
        return res.json({
            [name]: map[name] || null
        });
    }

    res.json(map);
});

// POST
app.post("/webhook", (req, res) => {
  //console.log("收到Harbor Webhook:", req.body);

  const event = req.body;
    if (event.type === "PUSH_ARTIFACT") {
      const repo = event.event_data.repository.repo_full_name;
      const tag = event.event_data.resources[0].tag || "latest";

      // 完整镜像
      const fullImage = `${HARBOR_DOMAIN}/${repo}:${tag}`;
      // 短镜像
      const shortImage = fullImage.split('/').pop();
      // 容器名
      const appContainer = shortImage.split(':')[0];

      // 动态分配端口
      const servicePort = allocatePort(appContainer);

      console.log("开始拉取并启动镜像:", fullImage);

      exec(`docker pull ${fullImage}`, (err) => {
            if (err) return console.error("拉取失败:", err);

            exec(`docker stop ${appContainer} || true && docker rm ${appContainer} || true`, () => {
                const cmd = `
                    docker run -d --restart=always \
                        --name ${appContainer} \
                        -p ${servicePort}:${servicePort} \
                        ${shortImage}
                `;
                exec(cmd, (err2) => {
                    if (err2) return console.error("容器启动失败:", err2);

		    console.log(`✔ 镜像成功启动: ${appContainer}（服务端口 ${servicePort}）`);

                    exec(`docker rmi -f ${fullImage}`, () => {
                        console.log("已删除带域名镜像:", fullImage);
                    });
                });
            });
      });
    }

  res.status(200).send("OK");
});

// POST 修改 / 新增端口
app.post("/db", async (req, res) => {
    const { name, port } = req.body;

    if (!name || port == null) {
        return res.status(400).json({
            error: "参数缺失，需要 { name, port }"
        });
    }

    // port 必须是数字
    if (typeof port !== "number" || isNaN(port)) {
        return res.status(400).json({ error: "port 必须是数字" });
    }

    // 范围限制
    if (port < PORT_MIN || port > PORT_MAX) {
        return res.status(400).json({
            error: `端口必须在范围 ${PORT_MIN} ~ ${PORT_MAX} 之间`
        });
    }

    const map = loadPortDB();

    // 检查端口是否被占用
    for (let key in map) {
        if (map[key] === port && key !== name) {
            return res.status(400).json({
                error: `端口 ${port} 已被 ${key} 占用`
            });
        }
    }

    // 设置端口
    map[name] = port;

    await savePortDB(map);

    res.json({
        message: "端口修改成功",
        name,
        port
    });
});

app.listen(9001, () => {
  console.log("Webhook server running on port 9001");
});
EOF

    # package.json
    sudo tee harbor-webhook/package.json > /dev/null <<'EOF'
{
  "name": "harbor-webhook",
  "version": "1.0.0",
  "main": "app.js",
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

    # Dockerfile
    sudo tee harbor-webhook/Dockerfile > /dev/null << 'EOF'
FROM node:18-alpine
RUN apk add --no-cache docker-cli
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 9001
CMD ["node", "app.js"]
EOF

    pushd harbor-webhook
        # 如果容器已存在则删除
        sudo docker rm -f harbor-webhook 2>/dev/null || true
        
        sudo docker build -t harbor-webhook .

        sudo docker run -d --restart=always \
            --name harbor-webhook \
            -p 9001:9001 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --env-file .env \
            harbor-webhook
    popd
}

# ============ 调用主流程 ============
main
