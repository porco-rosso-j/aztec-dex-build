use dep::aztec::protocol_types::traits::{Serialize, Deserialize};
use dep::std::ec::tecurve::affine::Point;
use crate::types::affine_point::AffinePoint;

// ( (x,y), (x,y) )
global ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN = 4;

/// @notice A struct representing the resulting ElGamal-encrypted points on the Baby Jubjub curve after performing encryption
///         on a value
/// @member C1 The point yielded by multiplying the base point of the Baby Jubjub curve by a provided randomness.
/// @member C2 The point yielded by adding the resulting plain_embedded (plaintext * base point) to the shared_secret (randomness * public key)
struct ElgamalAffinePoints {
    C1: AffinePoint,
    C2: AffinePoint
}

impl ElgamalAffinePoints {
    /// @notice Creates a new ElgamalAffinePoints starting from the given C1 and C2 points.
    /// @param point_C1 The C1 point to use
    /// @param point_C2 The C2 point to use
    pub fn new(point_C1: AffinePoint, point_C2: AffinePoint) -> Self {
        Self {
            C1: point_C1,
            C2: point_C2
        }
    }

    /// @notice Adds two ElgamalAffinePoints together
    /// @param second The second ElgamalAffinePoints to add
    fn add(self, second: ElgamalAffinePoints) -> Self {
        Self {
            C1: self.C1.add(second.C1),
            C2: self.C2.add(second.C2)
        }
    }

    // TODO: implement as trait when they are supported
    /// @notice Checks whether two ElgamalAffinePoints are equal (in the Baby Jubjub curve)
    /// @param second The second ElgamalAffinePoints to check
    fn eq(self, second: ElgamalAffinePoints) -> bool {
        self.C1.eq(second.C1) * self.C2.eq(second.C2)
    }
}

/// @notice Deserializes an array of Field elements into an AffinePoint
/// @param serialized The array of Field elements to be deserialized
impl Deserialize<ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN> for ElgamalAffinePoints {
    fn deserialize(fields: [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN]) -> Self {
        Self {
            C1: AffinePoint::new(
                Point{
                    x: fields[0],
                    y: fields[1]
                }
            ),
            C2: AffinePoint::new(
                Point{
                    x: fields[2],
                    y: fields[3]
                }
            )
        }
    }
}


/// @notice Serializes an AffinePoint into an array of Field elements
/// @param value The AffinePoint to be serialized
impl Serialize<ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN> for ElgamalAffinePoints {
    fn serialize(self) -> [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN] {
         [self.C1.point.x, self.C1.point.y, self.C2.point.x, self.C2.point.y]
    }
}
