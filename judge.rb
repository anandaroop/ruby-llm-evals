require "dotenv/load"
require "ruby_llm"
require "easy_talk"

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

def judge_output(input, output)
  RubyLLM.configure do |config|
    config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
    config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
    config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  end

  llm_judge = RubyLLM.chat(
    # model: "claude-sonnet-4-20250514"
    # model: "o3-mini"
    # model: "o4-mini"
    model: "gpt-4.1-mini"
    # model: "gemini-2.5-flash-preview-05-20"
  )

  llm_judge.with_instructions(
    <<~PROMPT
      Your task is to evaluate the quality of a response from another LLM, whose task was to extract artwork metadata from an arbitrary CSV and produce a structured JSON output.

      Each object in the JSON was extracted according to the following schema:

      <ARTWORK_SCHEMA>
      #{JSON.pretty_generate(Artwork.json_schema)}
      </ARTWORK_SCHEMA>

      Output should should be graded on the following scale:

      1: Poor quality, meets some requirements but has significant issues
      2: Acceptable quality, meets most requirements but may have some issues
      3: Good quality, meets all requirements with zero or minor issues

      Your response should be a record in the form:

      ```json
      [
        {
          "title": "<the title of the 1st artwork>",
          "grade": 3,
          "reason": "<whatever commentary you think would be helpful to explain the grade in 100 tokens or less>"
        },
        {
          "title": "<the title of the 2nd artwork>",
          "grade": 1,
          "reason": "<whatever commentary you think would be helpful to explain the grade in 100 tokens or less>"
        }
      ]
      ```
    PROMPT
  )

  response = llm_judge.with_temperature(0).ask(
    <<~PROMPT
      Evaluate the following output, compared to its input.

      <INPUT_CSV>
      #{input}
      </INPUT_CSV>

      <OUTPUT_JSON>
      #{output}
      </OUTPUT_JSON>

      Give your answer in valid JSON only, no markdown codefence.
    PROMPT
  ) { |chunk| print "." }
  puts
  JSON.parse(response.content)
end
