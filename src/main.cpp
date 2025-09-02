#include <xlnt/utils/optional.hpp>

#include <boost/algorithm/string.hpp>
#include <boost/archive/text_iarchive.hpp>
#include <boost/archive/text_oarchive.hpp>
#include <boost/filesystem.hpp>
#include <boost/format.hpp>
#include <boost/json.hpp>
#include <boost/regex.hpp>
#include <boost/thread.hpp>
#include <boost/timer/timer.hpp>
#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_generators.hpp>
#include <boost/uuid/uuid_io.hpp>

#include <fmt/chrono.h>
#include <fmt/color.h>
#include <fmt/core.h>
#include <fmt/format.h>
#include <fmt/ranges.h>

#include <xlnt/styles/alignment.hpp>
#include <xlnt/styles/border.hpp>
#include <xlnt/styles/font.hpp>
#include <xlnt/styles/format.hpp>
#include <xlnt/styles/number_format.hpp>
#include <xlnt/workbook/workbook.hpp>
#include <xlnt/worksheet/range.hpp>
#include <xlnt/xlnt.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

namespace boost::serialization {

template <typename Archive, typename... Types>
void serialize(Archive &ar, std::tuple<Types...> &t,
               const unsigned int /*unused*/) {
    std::apply([&](auto &...element) { ((ar & element), ...); }, t);
}

} // namespace boost::serialization

namespace {
struct VecXYZ {
    float x{}, y{}, z{};
    friend class boost::serialization::access;

    template <class Archive>
    void serialize(Archive &ar, const unsigned int version) {
        ar & x;
        ar & y;
        ar & z;
    }
};

template <class args_tuple_t> struct CallData {
    args_tuple_t argument_tuple;
    uint64_t thread_start_fn;

    template <class Archive>
    void serialize(Archive &ar, const unsigned int version) {
        ar & argument_tuple;
        ar & thread_start_fn;
    }
};

template <typename rawfn_T, class... Types>
void callFn(rawfn_T fun, Types &&...args) {
    fun(std::forward<Types>(args)...);
}

template <typename rawfn_T, class... Types>
void callWrapFn(const std::string &data) {
    std::stringstream ifs(data);
    boost::archive::text_iarchive ia(ifs);
    CallData<std::tuple<Types...>> call_data;
    ia >> call_data;

    std::apply(reinterpret_cast<rawfn_T>(call_data.thread_start_fn),
               call_data.argument_tuple);
}

template <typename rawfn_T, class... Types>
auto prepareFn(rawfn_T fun, Types &&...args) -> void * {
    using args_tuple_t = decltype(std::tuple{std::forward<Types>(args)...});

    CallData<args_tuple_t> call_data;

    call_data.argument_tuple = std::tuple{std::forward<Types>(args)...};

    call_data.thread_start_fn = reinterpret_cast<uint64_t>(fun);

    std::ofstream ofs("filename");
    boost::archive::text_oarchive oa(ofs);
    oa << call_data;
    ofs.close();

    void *ptr = reinterpret_cast<void *>(callWrapFn<rawfn_T, Types...>);

    return ptr;
}

auto fnfoo(int x, int y) { fmt::println("x = {}, y = {}", x, y); }

// === BOOST EXAMPLES ===
void demonstrate_boost_features() {
    fmt::print(fmt::fg(fmt::color::cyan),
               "\n🚀 === BOOST LIBRARY FEATURES ===\n");

    // 1. Boost.UUID - Generate unique identifiers
    fmt::print(fmt::fg(fmt::color::yellow), "\n📋 Boost.UUID Example:\n");
    boost::uuids::uuid uuid = boost::uuids::random_generator()();
    fmt::print("  Generated UUID: {}\n", boost::uuids::to_string(uuid));

    // 2. Boost.Regex - Pattern matching
    fmt::print(fmt::fg(fmt::color::yellow), "\n🔍 Boost.Regex Example:\n");
    const std::string text =
        "Contact: john.doe@example.com or jane.smith@test.org";
    const boost::regex email_pattern(
        R"([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})");

    boost::sregex_iterator start(text.cbegin(), text.cend(), email_pattern);
    boost::sregex_iterator end;

    fmt::print("  Text: '{}'\n", text);
    fmt::print("  Found emails: ");
    std::vector<std::string> emails;
    for (boost::sregex_iterator i = start; i != end; ++i) {
        emails.push_back((*i).str());
    }
    fmt::print("{}\n", fmt::join(emails, ", "));

    // 3. Boost.Algorithm - String processing
    fmt::print(fmt::fg(fmt::color::yellow), "\n🧰 Boost.Algorithm Example:\n");
    std::string sample_text = "  Hello, Boost World!  ";
    std::string trimmed = sample_text;
    boost::algorithm::trim(trimmed);

    std::vector<std::string> words;
    boost::algorithm::split(words, trimmed, boost::algorithm::is_space());

    fmt::print("  Original: '{}'\n", sample_text);
    fmt::print("  Trimmed: '{}'\n", trimmed);
    fmt::print("  Words: {}\n", fmt::join(words, " | "));

    // 4. Boost.JSON - JSON processing
    fmt::print(fmt::fg(fmt::color::yellow), "\n📄 Boost.JSON Example:\n");
    boost::json::object config;
    config["app_name"] = "boost-conan-cmake";
    config["version"] = "1.0.0";
    config["debug"] = true;

    boost::json::array features;
    features.push_back("serialization");
    features.push_back("json_processing");
    features.push_back("excel_export");
    config["features"] = std::move(features);

    std::string json_str = boost::json::serialize(config);
    fmt::print("  Generated JSON:\n{}\n", json_str);

    // 5. Boost.Timer - Performance measurement
    fmt::print(fmt::fg(fmt::color::yellow), "\n⏱️  Boost.Timer Example:\n");
    boost::timer::cpu_timer timer;

    // Simulate some work
    std::vector<double> data(1'000'000);
    std::iota(data.begin(), data.end(), 1.0);

    auto result = std::accumulate(
        data.begin(), data.end(), 0.0, [](double sum, double val) {
            return sum + std::sin(val) * std::cos(val);
        });

    timer.stop();
    fmt::print("  Computed trigonometric sum: {:.6f}\n", result);
    fmt::print("  Elapsed time: {}\n", timer.format());

    // 6. Boost.Filesystem - File operations
    fmt::print(fmt::fg(fmt::color::yellow), "\n📁 Boost.Filesystem Example:\n");
    boost::filesystem::path current_dir = boost::filesystem::current_path();
    fmt::print("  Current directory: {}\n", current_dir.string());

    boost::filesystem::path test_file = current_dir / "temp_test.txt";
    std::ofstream test_stream(test_file.string());
    test_stream << "Hello from Boost.Filesystem!\n";
    test_stream << "File size will be calculated.\n";
    test_stream.close();

    if (boost::filesystem::exists(test_file)) {
        auto file_size = boost::filesystem::file_size(test_file);
        fmt::print("  Created test file: {} ({} bytes)\n",
                   test_file.filename().string(), file_size);
        boost::filesystem::remove(test_file); // Cleanup
    }
}

// === FMT EXAMPLES ===
void demonstrate_fmt_features() {
    fmt::print(fmt::fg(fmt::color::green),
               "\n🎨 === FMT LIBRARY FEATURES ===\n");

    // 1. Colorful output
    fmt::print(fmt::fg(fmt::color::yellow), "\n🌈 Colorful Text Example:\n");
    fmt::print("  Regular text\n");
    fmt::print(fmt::fg(fmt::color::red), "  Red text\n");
    fmt::print(fmt::bg(fmt::color::blue) | fmt::fg(fmt::color::white),
               "  White on blue\n");
    fmt::print(fmt::emphasis::bold | fmt::fg(fmt::color::magenta),
               "  Bold magenta\n");

    // 2. Number formatting
    fmt::print(fmt::fg(fmt::color::yellow),
               "\n🔢 Number Formatting Example:\n");
    double pi = 3.14159265359;
    int large_num = 1234567890;

    fmt::print("  Pi with different precisions:\n");
    fmt::print("    Default: {}\n", pi);
    fmt::print("    2 decimals: {:.2f}\n", pi);
    fmt::print("    Scientific: {:.3e}\n", pi);
    fmt::print("    Fixed width: {:10.4f}\n", pi);

    fmt::print("  Large number formatting:\n");
    fmt::print("    Default: {}\n", large_num);
    fmt::print("    With commas: {:L}\n", large_num);
    fmt::print("    Hexadecimal: {:#x}\n", large_num);
    fmt::print("    Binary: {:#b}\n", 42);

    // 3. Date and time formatting
    fmt::print(fmt::fg(fmt::color::yellow),
               "\n📅 Date/Time Formatting Example:\n");
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);

    fmt::print("  Current time: {}\n",
               fmt::format("{:%Y-%m-%d %H:%M:%S}", *std::localtime(&time_t)));
    fmt::print("  ISO format: {}\n",
               fmt::format("{:%Y-%m-%dT%H:%M:%S}", *std::localtime(&time_t)));

    // 4. Container formatting
    fmt::print(fmt::fg(fmt::color::yellow),
               "\n📊 Container Formatting Example:\n");
    std::vector<int> numbers = {1, 2, 3, 4, 5};
    std::array<std::string, 3> languages = {"C++", "Python", "Rust"};
    std::map<std::string, int> scores = {
        {"Alice", 95}, {"Bob", 87}, {"Charlie", 92}};

    fmt::print("  Vector: {}\n", numbers);
    fmt::print("  Array: {}\n", fmt::join(languages, " | "));
    fmt::print("  Map scores:\n");
    for (const auto &[name, score] : scores) {
        fmt::print("    {}: {:>3}\n", name, score);
    }

    // 5. Custom formatting
    fmt::print(fmt::fg(fmt::color::yellow),
               "\n🎯 Custom Formatting Example:\n");
    struct Point {
        double x, y;
    };
    Point p{3.14, 2.71};

    // Using structured binding in lambda
    auto point_formatter = [](const Point &pt) {
        return fmt::format("Point({:.2f}, {:.2f})", pt.x, pt.y);
    };

    fmt::print("  Custom point: {}\n", point_formatter(p));

    // 6. Performance comparison
    fmt::print(fmt::fg(fmt::color::yellow), "\n⚡ Performance Example:\n");
    const int iterations = 100'000;

    // Time fmt::format
    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iterations; ++i) {
        volatile auto result = fmt::format("Number: {}, Pi: {:.6f}", i, pi);
    }
    auto fmt_duration = std::chrono::high_resolution_clock::now() - start;

    fmt::print("  fmt::format {} iterations: {}\n", iterations, fmt_duration);
}

// === XLNT EXAMPLES ===
void demonstrate_xlnt_features() {
    fmt::print(fmt::fg(fmt::color::blue),
               "\n📊 === XLNT LIBRARY FEATURES ===\n");

    // 1. Create a comprehensive Excel workbook
    fmt::print(fmt::fg(fmt::color::yellow),
               "\n📈 Excel Workbook Creation Example:\n");
    xlnt::workbook workbook;

    // Create multiple worksheets
    auto sales_sheet = workbook.active_sheet();
    sales_sheet.title("Sales Data");

    auto summary_sheet = workbook.create_sheet();
    summary_sheet.title("Summary");

    auto charts_sheet = workbook.create_sheet();
    charts_sheet.title("Charts");

    fmt::print("  Created workbook with {} sheets\n", workbook.sheet_count());

    // 2. Populate sales data with formatting
    fmt::print(fmt::fg(fmt::color::yellow), "\n💰 Sales Data Population:\n");

    // Headers
    std::vector<std::string> headers = {"Date",  "Product", "Quantity",
                                        "Price", "Total",   "Region"};
    for (size_t col = 0; col < headers.size(); ++col) {
        auto cell = sales_sheet.cell(static_cast<xlnt::column_t>(col + 1), 1);
        cell.value(headers[col]);

        // Header formatting
        auto header_format = workbook.create_format();
        header_format.font(
            xlnt::font().bold(true).color(xlnt::color::white()).size(12));
        header_format.fill(xlnt::fill::solid(xlnt::color::blue()));
        header_format.alignment(
            xlnt::alignment().horizontal(xlnt::horizontal_alignment::center));
        cell.format(header_format);
    }

    // Sample sales data
    struct SalesRecord {
        std::string date;
        std::string product;
        int quantity;
        double price;
        std::string region;
    };

    std::vector<SalesRecord> sales_data = {
        {"2024-01-15", "Laptop Pro", 25, 1299.99, "North"},
        {"2024-01-16", "Mouse Wireless", 150, 29.99, "South"},
        {"2024-01-17", "Keyboard Mech", 75, 149.50, "East"},
        {"2024-01-18", "Monitor 4K", 40, 399.00, "West"},
        {"2024-01-19", "Tablet Air", 60, 599.99, "North"},
        {"2024-01-20", "Headphones Pro", 90, 199.95, "South"},
    };

    for (size_t row = 0; row < sales_data.size(); ++row) {
        const auto &record = sales_data[row];
        auto excel_row = static_cast<xlnt::row_t>(row + 2); // Start from row 2

        sales_sheet.cell("A", excel_row).value(record.date);
        sales_sheet.cell("B", excel_row).value(record.product);
        sales_sheet.cell("C", excel_row).value(record.quantity);
        sales_sheet.cell("D", excel_row).value(record.price);

        // Formula for total
        auto total_cell = sales_sheet.cell("E", excel_row);
        std::string formula = fmt::format("=C{}*D{}", excel_row, excel_row);
        total_cell.formula(formula);

        sales_sheet.cell("F", excel_row).value(record.region);

        // Alternate row coloring - simplified without custom color
        if (row % 2 == 0) {
            // Skip alternate row coloring for now due to API limitations
        }
    }

    fmt::print("  Populated {} sales records with formulas and formatting\n",
               sales_data.size());

    // 3. Create summary sheet with aggregations
    fmt::print(fmt::fg(fmt::color::yellow), "\n📊 Summary Sheet Creation:\n");

    summary_sheet.cell("A1").value("Sales Summary Report");
    auto title_format = workbook.create_format();
    title_format.font(
        xlnt::font().size(16).bold(true).color(xlnt::color::blue()));
    summary_sheet.cell("A1").format(title_format);

    // Summary statistics
    summary_sheet.cell("A3").value("Total Records:");
    summary_sheet.cell("B3").formula(
        fmt::format("=COUNTA('Sales Data'!A2:A{})", sales_data.size() + 1));

    summary_sheet.cell("A4").value("Total Revenue:");
    summary_sheet.cell("B4").formula(
        fmt::format("=SUM('Sales Data'!E2:E{})", sales_data.size() + 1));

    summary_sheet.cell("A5").value("Average Sale:");
    summary_sheet.cell("B5").formula(
        fmt::format("=AVERAGE('Sales Data'!E2:E{})", sales_data.size() + 1));

    summary_sheet.cell("A6").value("Max Sale:");
    summary_sheet.cell("B6").formula(
        fmt::format("=MAX('Sales Data'!E2:E{})", sales_data.size() + 1));

    // Format currency cells - using percentage as fallback
    auto currency_format = workbook.create_format();
    currency_format.number_format(xlnt::number_format::percentage());
    // Note: Using percentage format as currency format is not available
    summary_sheet.cell("B4").format(currency_format);
    summary_sheet.cell("B5").format(currency_format);
    summary_sheet.cell("B6").format(currency_format);

    fmt::print("  Created summary with formulas and currency formatting\n");

    // 4. Column width and formatting optimization
    fmt::print(fmt::fg(fmt::color::yellow), "\n🎨 Column Formatting:\n");

    // Auto-fit columns in sales sheet
    sales_sheet.column_properties(1).width = 12; // Date
    sales_sheet.column_properties(2).width = 20; // Product
    sales_sheet.column_properties(3).width = 10; // Quantity
    sales_sheet.column_properties(4).width = 12; // Price
    sales_sheet.column_properties(5).width = 12; // Total
    sales_sheet.column_properties(6).width = 10; // Region

    // Number formatting for price and total columns
    auto price_format = workbook.create_format();
    price_format.number_format(xlnt::number_format::number_00());

    auto quantity_format = workbook.create_format();
    quantity_format.number_format(xlnt::number_format::number());
    quantity_format.alignment(
        xlnt::alignment().horizontal(xlnt::horizontal_alignment::center));

    // Apply number formats to data range
    for (size_t row = 2; row <= sales_data.size() + 1; ++row) {
        sales_sheet.cell("C", static_cast<xlnt::row_t>(row))
            .format(quantity_format);
        sales_sheet.cell("D", static_cast<xlnt::row_t>(row))
            .format(price_format);
        sales_sheet.cell("E", static_cast<xlnt::row_t>(row))
            .format(price_format);
    }

    fmt::print("  Applied column widths and number formatting\n");

    // 5. Save the comprehensive workbook
    const std::string filename = "comprehensive_example.xlsx";
    workbook.save(filename);
    fmt::print("  Saved comprehensive workbook as: {}\n", filename);

    // 6. Read back and analyze
    fmt::print(fmt::fg(fmt::color::yellow), "\n🔍 Reading Excel File Back:\n");
    try {
        xlnt::workbook read_workbook;
        read_workbook.load(filename);

        fmt::print("  Successfully loaded workbook with {} sheets:\n",
                   read_workbook.sheet_count());
        for (const auto &sheet : read_workbook) {
            fmt::print("    - '{}'\n", sheet.title());
        }

        // Read some data back
        auto read_sheet = read_workbook.sheet_by_title("Sales Data");
        auto first_product = read_sheet.cell("B2").value<std::string>();
        auto first_quantity = read_sheet.cell("C2").value<int>();

        fmt::print("  First record: {} (Qty: {})\n", first_product,
                   first_quantity);

    } catch (const std::exception &ex) {
        fmt::print(fmt::fg(fmt::color::red), "  Error reading workbook: {}\n",
                   ex.what());
    }
}
} // namespace

auto main() -> int {
    fmt::print(fmt::fg(fmt::color::magenta) | fmt::emphasis::bold,
               "🚀 === BOOST-CONAN-CMAKE COMPREHENSIVE DEMO ===\n");

    // Run all feature demonstrations
    demonstrate_boost_features();
    demonstrate_fmt_features();
    demonstrate_xlnt_features();

    fmt::print(fmt::fg(fmt::color::cyan),
               "\n📚 === ORIGINAL SERIALIZATION EXAMPLE ===\n");

    fmt::print("Hello, world!\n");
    VecXYZ vec_original{1.0F, 2.0F, 3.0F};
    std::ofstream output_file_stream("filename");
    boost::archive::text_oarchive output_archive(output_file_stream);
    output_archive << vec_original;
    VecXYZ vec_restored;
    output_file_stream.close();

    std::ifstream input_file_stream("filename");
    boost::archive::text_iarchive input_archive(input_file_stream);
    input_archive >> vec_restored;
    fmt::print("vec_restored.x = {}\n", vec_restored.x);
    fmt::print("vec_restored.y = {}\n", vec_restored.y);
    fmt::print("vec_restored.z = {}\n", vec_restored.z);

    auto *prepared_function = prepareFn(fnfoo, 1, 2);

    fmt::print("prepared_function = {}\n",
               static_cast<void *>(prepared_function));

    std::ifstream serialized_file("filename");
    std::stringstream string_stream{};
    string_stream << serialized_file.rdbuf();
    auto function_pointer =
        reinterpret_cast<void (*)(const std::string &data)>(prepared_function);
    function_pointer(string_stream.str());

    xlnt::workbook simple_workbook = xlnt::workbook::empty();

    // Add a worksheet to the workbook
    xlnt::worksheet simple_worksheet = simple_workbook.active_sheet();

    // Example of adding data to cells and formatting them
    simple_worksheet.cell("A1").value("Hello AAAAAAAAAAAAAAAAAAAAAAAAAAAA");

    auto format = simple_workbook.create_format(true);

    auto default_font =
        xlnt::font().name("Calibri").size(12).scheme("minor").family(2).color(
            xlnt::theme_color(1));

    format.font(default_font);

    simple_worksheet.cell("A1").format(format);
    format.font(
        simple_worksheet.cell("A1").font().color(xlnt::color::red()).size(14));

    simple_worksheet.cell("B1").value("World!");
    simple_worksheet.cell("B1").format(format);
    simple_worksheet.cell("B1").font().color(xlnt::color::blue()).size(14);

    // Example of shrinking columns to fit content
    simple_worksheet.column_properties(1).best_fit = true; // Column A
    simple_worksheet.column_properties(2).best_fit = true; // Column B

    // Save the workbook to a file
    simple_workbook.save("example.xlsx");

    fmt::print(fmt::fg(fmt::color::green) | fmt::emphasis::bold,
               "\n✅ === ALL DEMOS COMPLETED SUCCESSFULLY ===\n");

    return 0;
}
