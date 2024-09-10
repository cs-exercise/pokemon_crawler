require "db"
require "sqlite3"
require "http/client"
require "lexbor"
require "./pokemon_crawler"

start_idx = 1 # 爬取起始编号(最小支持编号：1)
end_idx = 3   # 爬取结束编号(最大支持编号：1025)

if start_idx < 1 || end_idx > 1025 || start_idx > end_idx
  abort "\n爬取范围错误，请修改 start 和 end 变量\n"
end

puts "\n开始爬取 #{start_idx} 到 #{end_idx} 号宝可梦数据...\n"

url_numbers = (start_idx..end_idx).map { |e| sprintf("%04d", e) }

IMAGE_DIR = "pokemon_images"
Dir.exists?(IMAGE_DIR) || Dir.mkdir_p(IMAGE_DIR)

db_file = "sqlite3:./pokemon_images.db"

PokemonCrawler.create_db(db_file)

url_numbers.each do |url_number|
  record = PokemonCrawler.fetch_pokemon_data(url_number)

  DB.connect db_file do |db|
    db.exec(<<-'HEREDOC', *record
INSERT INTO pokemon (
number, name, subname, height, weight,
sex, ability, classify, attribute, weakness,
photo, photo_path
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
HEREDOC
    )
  rescue e : SQLite3::Exception
    abort "Error creating table: #{e.message}"
  ensure
    db.close if db
  end
end

# code end
