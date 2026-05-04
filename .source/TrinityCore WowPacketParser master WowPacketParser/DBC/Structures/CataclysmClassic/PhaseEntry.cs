using DBCD.IO.Attributes;

namespace WowPacketParser.DBC.Structures.CataclysmClassic
{
    [DBFile("Phase")]
    public sealed class PhaseEntry
    {
        [Index(true)]
        public uint ID;
        public int Flags;
    }
}
