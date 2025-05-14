///
/// ERROR
///
pub const Error = error{
    UnexpectedErrorOnInit,
    InvalidFormat,
    InvalidValue,
    MissingSection,
    MissingKey,
    UnexpectedCharacter,
    CircularInclude,
    OutOfMemory, // Si vous gérez l'allocation manuellement et pouvez manquer de mémoire
};
