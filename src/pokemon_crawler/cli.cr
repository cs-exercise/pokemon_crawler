require "db"
require "sqlite3"
require "wait_group"
require "./pokemon_crawler"

start_idx = 1 # 爬取起始编号(最小支持编号：1)
end_idx = 25  # 爬取结束编号(最大支持编号：1025)

if start_idx < 1 || end_idx > 1025 || start_idx > end_idx
  abort "\n爬取范围错误，请修改 start 和 end 变量\n"
end

puts "\n开始爬取 #{start_idx} 到 #{end_idx} 号宝可梦数据...\n"

IMAGE_DIR = "pokemon_images"
Dir.exists?(IMAGE_DIR) || Dir.mkdir_p(IMAGE_DIR)

DB_FILE = "sqlite3:./pokemon_images.db"

PokemonCrawler.create_db(DB_FILE)

CONN = DB.open DB_FILE

total_size = end_idx - start_idx
worker_size = ENV.fetch("CRYSTAL_WORKERS", "8").to_i
batch_size = 30
batches = total_size // batch_size
channel = Channel({Int32, Int32}).new(batches)
wg = WaitGroup.new(worker_size)

worker_size.times do |i|
  spawn name: "Worker-#{i}" do
    while (r = channel.receive?)
      (r[0]..r[1]).each do |url_number|
        payload(url_number)
      end
    end
    wg.done
  end
end

r0 = 1

worker_size.times do
  r1 = r0 &+ batch_size
  channel.send({r0, r1})
  r0 = r1
end

if total_size > batch_size * batches
  channel.send({r0, total_size})
end

channel.close
wg.wait
CONN.close

def payload(url_number)
  number = sprintf("%04d", url_number)
  record = PokemonCrawler.fetch_pokemon_data(number)

  CONN.exec <<-'HEREDOC', *record
INSERT INTO pokemon (
number, name, subname, height, weight,
sex, ability, classify, attribute, weakness,
photo, photo_path
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
HEREDOC

rescue e : SQLite3::Exception
  STDOUT.puts "Error creating table: #{e.message}"
end
