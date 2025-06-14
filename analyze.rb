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

  def speed_vs_quality_scatter
    puts Rainbow("⚡🎯 SPEED vs QUALITY SCATTER PLOT").bright.cyan
    puts "=" * 60
    
    # Get data ranges
    speeds = @results.map { |r| r[:evaluation][:records_per_second].to_f }
    qualities = @results.map { |r| r[:evaluation][:average_llm_judgement].to_f }
    
    max_speed = speeds.max
    min_speed = speeds.min
    max_quality = qualities.max
    min_quality = qualities.min
    
    # Create 2D plot area
    plot_height = 10
    plot_width = 40
    
    # Create a grid to place models
    grid = Array.new(plot_height) { Array.new(plot_width, "·") }
    
    # Place each model on the grid
    @results.each do |result|
      eval = result[:evaluation]
      speed = eval[:records_per_second].to_f
      quality = eval[:average_llm_judgement].to_f
      
      # Convert to grid coordinates
      x = ((speed - min_speed) / (max_speed - min_speed) * (plot_width - 1)).round
      y = ((quality - min_quality) / (max_quality - min_quality) * (plot_height - 1)).round
      
      # Get model symbol
      model_name = result[:model].to_s
      symbol = case model_name
               when /claude-sonnet/ then Rainbow("S").green
               when /claude-haiku/ then Rainbow("H").yellow  
               when /claude-2/ then Rainbow("2").red
               when /gpt/ then Rainbow("G").blue
               when /o3/ then Rainbow("3").magenta
               when /o4/ then Rainbow("4").cyan
               else Rainbow("?").white
               end
      
      grid[y][x] = symbol
    end
    
    # Display the grid
    puts "Quality │"
    (0...plot_height).reverse_each do |y|
      quality_val = min_quality + (y / (plot_height - 1).to_f) * (max_quality - min_quality)
      printf "%7.2f │", quality_val
      
      (0...plot_width).each do |x|
        print grid[y][x]
      end
      puts
    end
    
    printf "%7s └", ""
    puts "─" * plot_width
    printf "%7s  ", ""
    (0..4).each { |i| printf "%8.2f", min_speed + i * (max_speed - min_speed) / 4 }
    puts
    printf "%7s  ", ""
    puts "Speed (records/sec)"
    puts
    
    # Show actual model positions
    puts "Models:"
    @results.each do |result|
      eval = result[:evaluation]
      model = result[:model].to_s[0..20]
      speed = eval[:records_per_second].to_f
      quality = eval[:average_llm_judgement].to_f
      
      symbol = case result[:model].to_s
               when /claude-sonnet/ then Rainbow("S").green
               when /claude-haiku/ then Rainbow("H").yellow  
               when /claude-2/ then Rainbow("2").red
               when /gpt/ then Rainbow("G").blue
               when /o3/ then Rainbow("3").magenta
               when /o4/ then Rainbow("4").cyan
               else Rainbow("?").white
               end
      
      puts "  #{symbol} #{model.ljust(20)} Speed: #{speed.round(2)}/s Quality: #{quality.round(2)}"
    end
    puts
  end

  def completeness_vs_accuracy_scatter
    puts Rainbow("📊✅ COMPLETENESS vs ACCURACY SCATTER PLOT").bright.cyan
    puts "=" * 60
    
    # Get data ranges  
    completenesses = @results.map { |r| r[:evaluation][:parsed_percentage].to_f }
    accuracies = @results.map { |r| r[:evaluation][:valid_record_percentage].to_f }
    
    max_completeness = completenesses.max
    min_completeness = completenesses.min
    max_accuracy = accuracies.max
    min_accuracy = accuracies.min
    
    # Create 2D plot area
    plot_height = 10
    plot_width = 40
    
    # Create a grid to place models
    grid = Array.new(plot_height) { Array.new(plot_width, "·") }
    
    # Place each model on the grid
    @results.each do |result|
      eval = result[:evaluation]
      completeness = eval[:parsed_percentage].to_f
      accuracy = eval[:valid_record_percentage].to_f
      
      # Skip models with 0 values that would cause division by zero
      next if max_completeness == min_completeness || max_accuracy == min_accuracy
      
      # Convert to grid coordinates
      x = ((completeness - min_completeness) / (max_completeness - min_completeness) * (plot_width - 1)).round
      y = ((accuracy - min_accuracy) / (max_accuracy - min_accuracy) * (plot_height - 1)).round
      
      # Get model symbol
      model_name = result[:model].to_s
      symbol = case model_name
               when /claude-sonnet/ then Rainbow("S").green
               when /claude-haiku/ then Rainbow("H").yellow  
               when /claude-2/ then Rainbow("2").red
               when /gpt/ then Rainbow("G").blue
               when /o3/ then Rainbow("3").magenta
               when /o4/ then Rainbow("4").cyan
               else Rainbow("?").white
               end
      
      # Handle overlapping markers by combining them
      if grid[y][x] != "·"
        # Already has a marker, combine them
        existing = grid[y][x]
        if existing.respond_to?(:uncolorize)
          existing_char = existing.uncolorize
        else
          existing_char = existing.to_s
        end
        
        new_char = case model_name
                   when /claude-sonnet/ then "S"
                   when /claude-haiku/ then "H"
                   when /claude-2/ then "2"
                   when /gpt/ then "G"
                   when /o3/ then "3"
                   when /o4/ then "4"
                   else "?"
                   end
        
        # Create combined marker with mixed colors
        combined = existing_char + new_char
        grid[y][x] = Rainbow(combined).bright
      else
        grid[y][x] = symbol
      end
    end
    
    # Display the grid
    puts "Accuracy │"
    (0...plot_height).reverse_each do |y|
      accuracy_val = min_accuracy + (y / (plot_height - 1).to_f) * (max_accuracy - min_accuracy)
      printf "%8.1f%% │", accuracy_val
      
      (0...plot_width).each do |x|
        print grid[y][x]
      end
      puts
    end
    
    printf "%8s └", ""
    puts "─" * plot_width
    printf "%8s  ", ""
    (0..4).each { |i| printf "%8.1f%%", min_completeness + i * (max_completeness - min_completeness) / 4 }
    puts
    printf "%8s  ", ""
    puts "Completeness (% records parsed)"
    puts
    
    # Show actual model positions
    puts "Models:"
    @results.each do |result|
      eval = result[:evaluation]
      model = result[:model].to_s[0..20]
      completeness = eval[:parsed_percentage].to_f
      accuracy = eval[:valid_record_percentage].to_f
      
      symbol = case result[:model].to_s
               when /claude-sonnet/ then Rainbow("S").green
               when /claude-haiku/ then Rainbow("H").yellow  
               when /claude-2/ then Rainbow("2").red
               when /gpt/ then Rainbow("G").blue
               when /o3/ then Rainbow("3").magenta
               when /o4/ then Rainbow("4").cyan
               else Rainbow("?").white
               end
      
      puts "  #{symbol} #{model.ljust(20)} Complete: #{completeness.round(1)}% Accuracy: #{accuracy.round(1)}%"
    end
    puts
  end

  def performance_matrix
    puts Rainbow("📈 PERFORMANCE MATRIX").bright.cyan
    puts "=" * 80
    
    # Create a matrix showing trade-offs
    metrics = %w[Quality Speed Accuracy Complete]
    models = @results.map { |r| r[:model].to_s[0..15] }
    
    printf "%-16s", "MODEL"
    metrics.each { |m| printf " %-8s", m }
    puts " RANK"
    puts "-" * 80
    
    @results.each_with_index do |result, idx|
      eval = result[:evaluation]
      model = result[:model].to_s[0..15]
      
      quality = eval[:average_llm_judgement].to_f
      speed = eval[:records_per_second].to_f
      accuracy = eval[:valid_record_percentage].to_f
      completeness = eval[:parsed_percentage].to_f
      
      # Normalize to 0-10 scale for visual consistency
      quality_norm = (quality / 3.0 * 10).round(1)
      speed_norm = (speed / @results.map { |r| r[:evaluation][:records_per_second].to_f }.max * 10).round(1)
      accuracy_norm = (accuracy / 10).round(1)
      completeness_norm = (completeness / 10).round(1)
      
      # Calculate overall rank (higher is better)
      overall_score = quality_norm + speed_norm + accuracy_norm + completeness_norm
      
      printf "%-16s", model
      printf " %8.1f", quality_norm
      printf " %8.1f", speed_norm  
      printf " %8.1f", accuracy_norm
      printf " %8.1f", completeness_norm
      printf " %4.1f", overall_score
      puts
    end
    puts
    puts "Scale: 0-10 (higher is better)"
    puts
  end

  def run_analysis
    total_runs = @all_results.length
    unique_models = @all_results.map { |r| r[:model] }.uniq.length

    puts Rainbow("🔍 ANALYZING #{total_runs} RUNS ACROSS #{unique_models} MODELS").bright.magenta
    puts

    summary_table
    speed_analysis
    quality_analysis
    speed_vs_quality_scatter
    completeness_vs_accuracy_scatter
    performance_matrix
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
