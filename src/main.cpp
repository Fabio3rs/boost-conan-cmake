#include <boost/archive/text_iarchive.hpp>
#include <boost/archive/text_oarchive.hpp>
#include <fmt/core.h>
#include <fstream>

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
} // namespace

int main() {
    fmt::print("Hello, world!\n");
    VecXYZ v1{1.0F, 2.0F, 3.0F};
    std::ofstream ofs("filename");
    boost::archive::text_oarchive oa(ofs);
    oa << v1;
    VecXYZ v2;
    ofs.close();

    std::ifstream ifs("filename");
    boost::archive::text_iarchive ia(ifs);
    ia >> v2;
    fmt::print("v2.x = {}\n", v2.x);
    fmt::print("v2.y = {}\n", v2.y);
    fmt::print("v2.z = {}\n", v2.z);
    return 0;
}
