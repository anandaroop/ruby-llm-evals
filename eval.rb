require "dotenv/load"
require "ruby_llm"
require "easy_talk"
require "csv"
require "rainbow"
require "./judge"

### DEFINE A VALIDATION SCHEMA (WILL BE SUPPLIED TO MODEL AS WELL AS USED FOR EVALUATION)

class Artwork
  include EasyTalk::Model

  define_schema do
    title "Artwork"
    description "An individual artwork"
    property :inventoryID, T.nilable(String), description: "Unique identified for the artwork in the uploader's inventory system"
    property :artistNames, T.nilable(String), description: "The names of the artist(s) associated with the artwork"
    property :title, T.nilable(String), description: "The artwork's title. Preserve the original casing and formatting."
    property :date, T.nilable(String), description: "The year the artwork was created (not acquired or accessioned). May include qualifiers such as 'circa'."
    property :price, T.nilable(String), description: 'The price of the artwork. It is assumed to be USD, and if so can be returned as a simple decimal number. But if there is another currency in the input, include it explicitly in the output. Examples: "420.42" for a USD price, or "420.42 EUR" for a Euro price.'
    property :medium, T.nilable(String), description: "The medium of the artwork, such as Painting, Sculpture, Photography, etc.", enum: ["Painting", "Sculpture", "Photography", "Print", "Drawing, Collage or other Work on Paper", "Mixed Media", "Performance Art", "Installation", "Video/Film/Animation", "Architecture", "Fashion Design and Wearable Art", "Jewelry", "Design/Decorative Art", "Textile Arts", "Posters", "Books and Portfolios", "Ephemera or Merchandise", "Reproduction", "NFT", "Digital Art", "Other"]
    property :materials, T.nilable(String), description: "The medium of the artwork, such as Painting, Sculpture, Photography, etc."
    property :height, T.nilable(String), description: "The height of the artwork. It is assumed to be in inches, but if there is another unit in the input, include it explicitly in the output. Examples: '12' for 12 inches, or '30 cm' for 30 centimeters."
    property :width, T.nilable(String), description: "The width of the artwork. It is assumed to be in inches, but if there is another unit in the input, include it explicitly in the output. Examples: '12' for 12 inches, or '30 cm' for 30 centimeters."
    property :depth, T.nilable(String), description: "The depth of the artwork. It is assumed to be in inches, but if there is another unit in the input, include it explicitly in the output. Examples: '12' for 12 inches, or '30 cm' for 30 centimeters."
    property :diameter, T.nilable(String), description: "The diameter of the artwork, if it is round. It is assumed to be in inches, but if there is another unit in the input, include it explicitly in the output. Examples: '12' for 12 inches, or '30 cm' for 30 centimeters."
    property :certificateOfAuthenticity, T::Boolean, description: "Whether the artwork comes with a certificate of authenticity. If the input is not clear, assume it does not."
    property :signature, T::Boolean, description: "The signature of the artist on the artwork, if applicable. If the input is not clear, assume it does not have a signature."
    additional_properties false
  end
end

### CREATE A SYSTEM PROMPT THAT INCLUDES A JSON SCHEMA

SYSTEM_PROMPT = <<~PROMPT
  You are an expert in extracting and formatting artwork data.

  Your task is to read the provided CSV file and extract relevant artwork data into a structured JSON format.

  The output should be a JSON array of objects, where each object represents an individual artwork that conforms to the following schema:

  <ARTWORK_SCHEMA>

  #{JSON.pretty_generate(Artwork.json_schema)}

  </ARTWORK_SCHEMA>

  Observe the following rules when extracting data:

  - Extract **ALL rows up to 100** – **NO EXCEPTIONS**
  - **Do not truncate** or provide "sample" output
  - Use proper Sentence and Title Case where appropriate. **Never ALL CAPS**.
PROMPT

### SOME CSV TO SUPPLY AS INPUT

# TEST_CSV = File.read("./files/granary-full.csv")
TEST_CSV = File.read("./files/granary-tiny.csv")

### CREATE A USER PROMPT THAT INCLUDES THE CSV TO BE PARSED

USER_PROMPT = <<~PROMPT
  Extract all artwork data from the attached file.

  Output valid json only, with no extra markdown, codefence or commentary.

  <FILE>

  #{TEST_CSV}

  </FILE>
PROMPT

# ### MAYBE DISPLAY THE FINAL PROMPTS
#
# puts SYSTEM_PROMPT
# puts USER_PROMPT

### GET THE RESPONSE FROM THE LLM

# MODEL = "claude-2.0" # lol
# MODEL = "claude-3-5-haiku"
MODEL = "claude-sonnet-4-20250514"
# MODEL = "gpt-4.1"
# MODEL = "o3-mini"
# MODEL = "o4-mini"
# MODEL = "gemini-2.5-flash-preview-05-20" # hmm doesn't work

puts "Parsing with model: #{MODEL}..."

RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
end

llm_parser = RubyLLM.chat(model: MODEL)
llm_parser.with_instructions(SYSTEM_PROMPT)

response = nil
benchmark = Benchmark.measure do
  response = llm_parser.with_temperature(0).ask(USER_PROMPT) { |chunk| print chunk.content }
end
puts

### SPECIFY AN IDEAL OUTPUT FOR THE SUPPLIED INPUT

IDEAL_OUTPUT = <<~JSON
  [
    {
      "inventoryID": "AR000006",
      "artistNames": "Nancy Slonim Aronie",
      "title": "A Blessing On Your House",
      "date": null,
      "price": "800.00",
      "medium": "Mixed Media",
      "materials": "METAL ELEPHANT (GANESH) on lucite block on nails with patina copper arch with adorable couple just about to kiss",
      "height": "7.00",
      "width": "6.00",
      "depth": "4.00",
      "diameter": null,
      "certificateOfAuthenticity": false,
      "signature": false
    },
    {
      "inventoryID": "SL000002",
      "artistNames": "Nancy Slonim Aronie",
      "title": "A Checkered Past",
      "date": "2023",
      "price": "1200.00 EUR",
      "medium": "Mixed Media",
      "materials": null,
      "height": null,
      "width": null,
      "depth": null,
      "diameter": null,
      "certificateOfAuthenticity": false,
      "signature": false
    }
  ]
JSON

## EVALUATE THE RESPONSE

evaluation = {
  valid_json: false,
  golden: false,
  golden_case_insensitive: false,
  row_count: 0,
  record_count: 0,
  parsed_percentage: 0,
  valid_record_count: 0,
  valid_record_percentage: 0,
  validation_error_count: 0,
  duration_seconds: 0,
  records_per_second: 0,
  seconds_per_record: 0,
  average_llm_judgement: 0
}

parsed = begin
  JSON.parse(response.content)
rescue
  puts Rainbow("Invalid JSON response").red
end

if parsed&.is_a?(Array)
  evaluation[:valid_json] = true
  evaluation[:golden] = JSON.parse(IDEAL_OUTPUT).eql?(parsed)
  evaluation[:golden_case_insensitive] = JSON.parse(IDEAL_OUTPUT.downcase).eql?(JSON.parse(response.content.downcase))
  evaluation[:row_count] = CSV.parse(TEST_CSV, headers: true).length
  evaluation[:record_count] = parsed.length
  evaluation[:parsed_percentage] = (evaluation[:record_count].to_f / evaluation[:row_count]) * 100
  evaluation[:valid_record_count] = parsed.count { |record| Artwork.new(record).valid? }
  evaluation[:valid_record_percentage] = (evaluation[:valid_record_count].to_f / evaluation[:record_count]) * 100
  evaluation[:validation_error_count] = parsed.map { |record| Artwork.new(record).errors.count }.sum
  evaluation[:duration_seconds] = benchmark.real.round(2)
  evaluation[:records_per_second] = (evaluation[:record_count].to_f / evaluation[:duration_seconds]).round(2)
  evaluation[:seconds_per_record] = (evaluation[:duration_seconds].to_f / evaluation[:record_count]).round(2)

  print "Getting LLM judgements"
  llm_judgements = judge_output(TEST_CSV, response.content)
  if llm_judgements.length == parsed.length
    evaluation[:average_llm_judgement] = (llm_judgements.map { |judgement| judgement["grade"] }.sum.to_f / llm_judgements.length).round(4)
  end
end

puts "\nResult:\n"
puts JSON.pretty_generate(evaluation)

## SAVE THE COMPLETE RESULTS

result = {
  model: MODEL,
  system_prompt: SYSTEM_PROMPT,
  user_prompt: USER_PROMPT,
  input: TEST_CSV,
  output: response.content,
  ideal_output: IDEAL_OUTPUT,
  evaluation: evaluation
}

filename = "results/artwork_imports_eval_#{Time.now.strftime("%Y%m%d_%H%M%S")}.yaml"
File.write(filename, result.to_yaml)

puts "\nSaved to #{filename}"
