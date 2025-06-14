# ✨ This file is just about all Claude ✨

require "yaml"
require "rainbow"
require "csv"
require "time"

class ResultsAnalyzer
  def initialize(results_dir = "./results", mode = :best)
    @results_dir = results_dir
    @all_results = load_all_results
    @mode = mode # :best, :latest, :all
    @results = filter_results(@all_results, @mode)
  end

  def load_all_results
    Dir.glob(File.join(@results_dir, "*.yaml")).map do |file|
      result = YAML.load_file(file)
      result[:filename] = File.basename(file)
      result[:timestamp] = extract_timestamp(file)
      result
    end.sort_by { |r| r[:timestamp] }
  end

  def extract_timestamp(filename)
    match = filename.match(/(\d{8}_\d{6})/)
    match ? Time.strptime(match[1], "%Y%m%d_%H%M%S") : Time.at(0)
  end

  def filter_results(all_results, mode)
    case mode
    when :all
      all_results
    when :latest
      # Group by model, take latest for each
      all_results.group_by { |r| r[:model] }.map do |model, runs|
        runs.max_by { |r| r[:timestamp] }
      end
    when :best
      # Group by model, take best quality score for each
      all_results.group_by { |r| r[:model] }.map do |model, runs|
        runs.max_by { |r| r[:evaluation][:average_llm_judgement].to_f }
      end
    end
  end

  def summary_table
    mode_label = case @mode
    when :best then "BEST RUNS"
    when :latest then "LATEST RUNS"
    when :all then "ALL RUNS"
    end

    puts Rainbow("🏆 MODEL PERFORMANCE LEADERBOARD (#{mode_label})").bright.cyan
    puts "=" * 80

    # Sort by average LLM judgement first, then by valid record percentage
    sorted_results = @results.sort_by do |r|
      eval = r[:evaluation]
      [-eval[:average_llm_judgement].to_f, -eval[:valid_record_percentage].to_f]
    end

    # Table headers
    printf "%-20s %-8s %-8s %-8s %-10s %-8s %-12s\n",
      "MODEL", "QUALITY", "ACCURACY", "COMPLETE", "SPEED", "ERRORS", "RUNS"
    puts "-" * 80

    sorted_results.each_with_index do |result, index|
      eval = result[:evaluation]
      model = result[:model]

      # Count runs for this model
      run_count = @all_results.count { |r| r[:model] == model }

      # Color coding based on rank
      color = case index
      when 0 then :green  # 1st place
      when 1 then :yellow # 2nd place
      when 2 then :cyan   # 3rd place
      else :white
      end

      quality = eval[:average_llm_judgement].to_f.round(2)
      accuracy = "#{eval[:valid_record_percentage].to_f.round(1)}%"
      completeness = "#{eval[:parsed_percentage].to_f.round(1)}%"
      speed = "#{eval[:records_per_second].to_f.round(2)}/s"
      errors = eval[:validation_error_count]

      printf Rainbow("%-20s %-8s %-8s %-8s %-10s %-8s %-12s\n").color(color),
        model.to_s[0..19], quality, accuracy, completeness, speed, errors, run_count
    end
    puts
  end

  def detailed_metrics
    puts Rainbow("📊 DETAILED METRICS").bright.cyan
    puts "=" * 80

    @results.each do |result|
      eval = result[:evaluation]
      model = result[:model]

      puts Rainbow("#{model}").bright.white
      puts "  JSON Valid: #{status_icon(eval[:valid_json])}"
      puts "  Golden Match: #{status_icon(eval[:golden])}"
      puts "  Records: #{eval[:record_count]}/#{eval[:row_count]} (#{eval[:parsed_percentage].round(1)}%)"
      puts "  Valid Records: #{eval[:valid_record_count]} (#{eval[:valid_record_percentage].round(1)}%)"
      puts "  LLM Judgment: #{eval[:average_llm_judgement].round(3)}/3.0"
      puts "  Duration: #{eval[:duration_seconds]}s"
      puts "  Speed: #{eval[:records_per_second].round(2)} records/sec"
      puts "  Errors: #{eval[:validation_error_count]}"
      puts
    end
  end

  def speed_analysis
    puts Rainbow("⚡ SPEED ANALYSIS").bright.cyan
    puts "=" * 50

    speed_data = @results.map do |r|
      {
        model: r[:model],
        speed: r[:evaluation][:records_per_second].to_f,
        duration: r[:evaluation][:duration_seconds].to_f
      }
    end.sort_by { |d| -d[:speed] }

    max_speed = speed_data.first[:speed]

    speed_data.each do |data|
      bar_length = ((data[:speed] / max_speed) * 30).to_i
      bar = "█" * bar_length + "░" * (30 - bar_length)

      color = if data[:speed] > max_speed * 0.7
        :green
      else
        (data[:speed] > max_speed * 0.4) ? :yellow : :red
      end

      puts Rainbow("#{data[:model].to_s.ljust(25)} #{bar} #{data[:speed].round(2)}/s").color(color)
    end
    puts
  end

  def quality_analysis
    puts Rainbow("🎯 QUALITY ANALYSIS").bright.cyan
    puts "=" * 50

    quality_data = @results.map do |r|
      {
        model: r[:model],
        quality: r[:evaluation][:average_llm_judgement].to_f,
        accuracy: r[:evaluation][:valid_record_percentage].to_f
      }
    end.sort_by { |d| -d[:quality] }

    max_quality = 3.0 # LLM judgment scale is 1-3

    quality_data.each do |data|
      bar_length = ((data[:quality] / max_quality) * 30).to_i
      bar = "█" * bar_length + "░" * (30 - bar_length)

      color = if data[:quality] > 2.5
        :green
      else
        (data[:quality] > 2.0) ? :yellow : :red
      end

      puts Rainbow("#{data[:model].to_s.ljust(25)} #{bar} #{data[:quality].round(2)}/3.0").color(color)
    end
    puts
  end

  def export_csv
    csv_file = "results_summary.csv"

    CSV.open(csv_file, "w") do |csv|
      # Headers
      csv << %w[model quality_score accuracy_pct completeness_pct speed_rps errors duration_sec filename]

      @results.each do |result|
        eval = result[:evaluation]
        csv << [
          result[:model],
          eval[:average_llm_judgement].to_f.round(3),
          eval[:valid_record_percentage].to_f.round(1),
          eval[:parsed_percentage].to_f.round(1),
          eval[:records_per_second].to_f.round(2),
          eval[:validation_error_count],
          eval[:duration_seconds],
          result[:filename]
        ]
      end
    end

    puts Rainbow("📄 Exported summary to #{csv_file}").green
  end

  def model_evolution
    return if @mode == :best || @mode == :latest

    puts Rainbow("📈 MODEL EVOLUTION").bright.cyan
    puts "=" * 80

    @all_results.group_by { |r| r[:model] }.each do |model, runs|
      next if runs.length < 2

      puts Rainbow("#{model}").bright.white
      runs.each_with_index do |run, i|
        eval = run[:evaluation]
        timestamp = run[:timestamp].strftime("%m/%d %H:%M")
        trend = if i > 0
          prev_quality = runs[i - 1][:evaluation][:average_llm_judgement].to_f
          curr_quality = eval[:average_llm_judgement].to_f
          if curr_quality > prev_quality
            Rainbow("↗").green
          elsif curr_quality < prev_quality
            Rainbow("↘").red
          else
            Rainbow("→").yellow
          end
        else
          " "
        end

        printf "  %s %s Quality: %.2f Speed: %.2f/s Records: %d/%d\n",
          timestamp, trend, eval[:average_llm_judgement].to_f,
          eval[:records_per_second].to_f, eval[:record_count], eval[:row_count]
      end
      puts
    end
  end

  def run_analysis
    total_runs = @all_results.length
    unique_models = @all_results.map { |r| r[:model] }.uniq.length

    puts Rainbow("🔍 ANALYZING #{total_runs} RUNS ACROSS #{unique_models} MODELS").bright.magenta
    puts

    summary_table
    speed_analysis
    quality_analysis
    model_evolution if @mode == :all
    detailed_metrics
    export_csv
  end

  private

  def status_icon(status)
    status ? Rainbow("✓").green : Rainbow("✗").red
  end
end

# Run the analysis
if __FILE__ == $0
  mode = ARGV[0]&.to_sym || :best

  unless [:best, :latest, :all].include?(mode)
    puts "Usage: ruby analyze.rb [best|latest|all]"
    puts "  best   - Show best run per model (default)"
    puts "  latest - Show latest run per model"
    puts "  all    - Show all runs with evolution tracking"
    exit 1
  end

  analyzer = ResultsAnalyzer.new("./results", mode)
  analyzer.run_analysis
end
