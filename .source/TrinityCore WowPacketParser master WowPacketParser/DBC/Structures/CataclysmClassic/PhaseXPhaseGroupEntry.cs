using DBCD.IO.Attributes;

namespace WowPacketParser.DBC.Structures.CataclysmClassic
{
    [DBFile("PhaseXPhaseGroup")]
    public sealed class PhaseXPhaseGroupEntry
    {
        [Index(true)]
        public uint ID;
        public ushort PhaseID;
        [Relation(typeof(uint), true)]
        public int PhaseGroupID;
    }
}
