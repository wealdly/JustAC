using DBCD.IO.Attributes;

namespace WowPacketParser.DBC.Structures.Midnight
{
    [DBFile("BroadcastTextDuration")]
    public sealed class BroadcastTextDurationEntry
    {
        [Index(true)]
        public uint ID;
        public int Locale;
        public int DurationMS;
        [Relation(typeof(uint), true)]
        public int BroadcastTextID;
    }
}
