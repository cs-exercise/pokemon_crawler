require "http/client"
require "lexbor"

module PokemonCrawler
  extend self

  def create_db(db_file)
    DB.connect db_file do |db|
      db.exec <<-'HEREDOC'
  create table if not exists pokemon (
         id INTEGER PRIMARY KEY,
         number TEXT,
         name TEXT,
         subname TEXT,
         height TEXT,
         weight TEXT,
         gender INTEGER,
         ability TEXT,
         classify TEXT,
         attribute TEXT,
         weakness TEXT,
         photo TEXT,
         photo_path TEXT
                  )
HEREDOC

    rescue e : SQLite3::Exception
      abort "Error creating table: #{e.message}"
    ensure
      db.close if db
    end
  end

  def download_image(image_url, pokemon_number)
    base_url = "https://www.pokemon.cn"

    response = get_request base_url + image_url

    if !"image".in? response.headers["Content-Type"]
      abort "错误： URL #{image_url} 不是有效的图片"
    end

    file_path = Path[IMAGE_DIR, "#{pokemon_number}.png"]

    until Dir.glob(file_path).empty?
      file_path = Path[IMAGE_DIR, "#{pokemon_number}_#{rand(1..1000)}.png"]
    end

    File.open(file_path, "wb") do |file|
      file.write(response.body.to_slice)
    end

    puts "图片已保存： #{file_path}"

    file_path
  rescue e : Socket::Error
    abort "下载图片时发生错误：#{e.message}"
  end

  def get_request(url)
    user_agent_list = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.1 (KHTML, like Gecko) Chrome/22.0.1207.1 Safari/537.1",
      "Mozilla/5.0 (X11; CrOS i686 2268.111.0) AppleWebKit/536.11 (KHTML, like Gecko) Chrome/20.0.1132.57 Safari/536.11",
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/536.6 (KHTML, like Gecko) Chrome/20.0.1092.0 Safari/536.6",
      "Mozilla/5.0 (Windows NT 6.2) AppleWebKit/536.6 (KHTML, like Gecko) Chrome/20.0.1090.0 Safari/536.6",
      "Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.1 (KHTML, like Gecko) Chrome/19.77.34.5 Safari/537.1",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/536.5 (KHTML, like Gecko) Chrome/19.0.1084.9 Safari/536.5",
      "Mozilla/5.0 (Windows NT 6.0) AppleWebKit/536.5 (KHTML, like Gecko) Chrome/19.0.1084.36 Safari/536.5",
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/536.3 (KHTML, like Gecko) Chrome/19.0.1063.0 Safari/536.3",
      "Mozilla/5.0 (Windows NT 5.1) AppleWebKit/536.3 (KHTML, like Gecko) Chrome/19.0.1063.0 Safari/536.3",
    ]

    response = HTTP::Client.get(url, headers: HTTP::Headers{"User-Agent" => user_agent_list.sample})

    if response.status_code == 200
      response
    else
      raise "Host #{url} return #{response.status_code}"
    end
  end

  def fetch_pokemon_data(url_number)
    response = get_request "https://www.pokemon.cn/play/pokedex/#{url_number}"
    parser = Lexbor::Parser.new(response.body)

    number = parser.css("p.pokemon-slider__main-no.size-28").first.tag_text.strip
    name = parser.css("p.pokemon-slider__main-name.size-35").first.tag_text.strip
    subname = parser.css("p.pokemon-slider__main-subname.size-20").first.tag_text.strip
    height = parser.css("div.pokemon-info__height span.pokemon-info__value.size-14").first?.try &.tag_text.strip
    weight = parser.css("div.pokemon-info__weight span.pokemon-info__value.size-14").first?.try &.tag_text.strip

    set = Set(String).new
    genders = parser.css("div.pokemon-info__gender img").map &.[]("src")

    genders.each do |e|
      set.add("男") if e.matches? /icon_male/
      set.add("女") if e.matches? /icon_female/
    end

    set1 = Set(String).new
    parser.css("div.pokemon-info__abilities span.pokemon-info__value.size-14").each do |e|
      set1.add(e.tag_text.strip)
    end

    classify = parser.css("div.pokemon-info__category span.pokemon-info__value.size-14").first?.try &.tag_text.strip

    attributes = parser.css("div.pokemon-type div.pokemon-type__type span").map &.tag_text.strip

    weakness = parser.css("div.pokemon-weakness div.pokemon-weakness__btn span").map &.tag_text.strip

    photo_url = parser.css("img.pokemon-img__front").first?.try &.[]("src")

    photo_path = ""

    photo_path = download_image(photo_url, url_number) if photo_url

    {number, name, subname, height, weight, set.join(","), set1.join(","), classify, attributes.join(","), weakness.join(","), photo_url.to_s, photo_path.to_s}
  end
end
